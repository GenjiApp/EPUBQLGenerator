#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <QuickLook/QuickLook.h>
#import <Cocoa/Cocoa.h>
#import "GNJUnZip.h"

static const NSInteger kMaximumNumberOfLoadingHTML = 10;
static const NSInteger kMaximumNumberOfLoadingImage = 10;
static const NSInteger kLoadAllFiles = -1;

/* -----------------------------------------------------------------------------
   Generate a preview for file

   This function's job is to create preview for designated file
   ----------------------------------------------------------------------------- */

OSStatus GeneratePreviewForURL(void *thisInterface,
                               QLPreviewRequestRef preview,
                               CFURLRef url,
                               CFStringRef contentTypeUTI,
                               CFDictionaryRef options)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  NSInteger maximumNumberOfLoadingHTML = kMaximumNumberOfLoadingHTML;
  NSInteger maximumNumberOfLoadingImage = kMaximumNumberOfLoadingImage;
  CFBundleRef bundleRef = QLPreviewRequestGetGeneratorBundle(preview);
  CFStringRef appId = CFBundleGetIdentifier(bundleRef);
  CFStringRef key = (CFStringRef)@"MaximumNumberOfLoadingHTML";
  CFPropertyListRef plistRef = CFPreferencesCopyAppValue(key, appId);
  if(plistRef) {
    maximumNumberOfLoadingHTML = [(NSNumber *)plistRef integerValue];
    CFRelease(plistRef);
  }
  key = (CFStringRef)@"MaximumNumberOfLoadingImage";
  plistRef = CFPreferencesCopyAppValue(key, appId);
  if(plistRef) {
    maximumNumberOfLoadingImage = [(NSNumber *)plistRef integerValue];
    CFRelease(plistRef);
  }

  NSString *path = [(NSURL *)url path];
  GNJUnZip *unzip = [[GNJUnZip alloc] initWithZipFile:path];

  NSCharacterSet *setForTrim = [NSCharacterSet whitespaceAndNewlineCharacterSet];

  // Get the path of .opf file
  NSData *xmlData = [unzip dataWithContentsOfFile:@"META-INF/container.xml"];
  if(!xmlData) {
    [unzip release];
    [pool release];
    return noErr;
  }

  NSXMLDocument *xmlDoc = [[NSXMLDocument alloc] initWithData:xmlData
                                                      options:NSXMLDocumentTidyXML
                                                        error:NULL];
  if(!xmlDoc) {
    [unzip release];
    [pool release];
    return noErr;
  }

  NSString *xpath = @"/container/rootfiles/rootfile/@full-path";
  NSArray *nodes = [xmlDoc nodesForXPath:xpath error:NULL];
  if(![nodes count]) {
    NSLog(@"no such nodes for xpath '%@'", xpath);
    [xmlDoc release];
    [unzip release];
    [pool release];
    return noErr;
  }

  NSXMLNode *fullPathNode = [nodes objectAtIndex:0];
  NSString *fullPathValue =[fullPathNode stringValue];
  NSString *opfFilePath = [fullPathValue stringByTrimmingCharactersInSet:setForTrim];
  opfFilePath = [opfFilePath stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
  [xmlDoc release];


  // Get the path of HTML files
  xmlData = [unzip dataWithContentsOfFile:opfFilePath];
  if(!xmlData) {
    [unzip release];
    [pool release];
    return noErr;
  }

  xmlDoc = [[NSXMLDocument alloc] initWithData:xmlData
                                       options:NSXMLDocumentTidyXML
                                         error:NULL];
  if(!xmlDoc) {
    [unzip release];
    [pool release];
    return noErr;
  }

  xpath = @"/package/manifest/item";
  nodes = [xmlDoc nodesForXPath:xpath error:NULL];
  if(![nodes count]) {
    NSLog(@"no such nodes for xpath '%@'", xpath);
    [xmlDoc release];
    [unzip release];
    [pool release];
    return noErr;
  }

  NSMutableDictionary *manifest = [NSMutableDictionary dictionary];
  for(NSXMLElement *elem in nodes) {
    NSXMLNode *idNode = [elem attributeForName:@"id"];
    NSXMLNode *hrefNode = [elem attributeForName:@"href"];
    NSString *key = [[idNode stringValue] stringByTrimmingCharactersInSet:setForTrim];
    NSString *path = [[hrefNode stringValue] stringByTrimmingCharactersInSet:setForTrim];
    path = [path stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    [manifest setObject:path forKey:key];
  }

  xpath = @"/package/spine/itemref/@idref";
  nodes = [xmlDoc nodesForXPath:xpath error:NULL];
  if(![nodes count]) {
    NSLog(@"no such nodes for xpath '%@'", xpath);
    [xmlDoc release];
    [unzip release];
    [pool release];
    return noErr;
  }

  NSUInteger numberOfHTML = 0;
  NSMutableArray *htmlPaths = [NSMutableArray array];
  NSString *opfBasePath = [opfFilePath stringByDeletingLastPathComponent];
  for(NSXMLNode *node in nodes) {
    NSString *idref = [[node stringValue] stringByTrimmingCharactersInSet:setForTrim];
    NSString *hrefValue = [manifest objectForKey:idref];
    if(![hrefValue length]) continue;
    NSString *htmlPath = nil;
    if([hrefValue isAbsolutePath]) htmlPath = [hrefValue substringFromIndex:1];
    else htmlPath = [opfBasePath stringByAppendingPathComponent:hrefValue];
    [htmlPaths addObject:htmlPath];

    if(maximumNumberOfLoadingHTML != kLoadAllFiles &&
       ++numberOfHTML >= maximumNumberOfLoadingHTML) break;
  }
  [xmlDoc release];

  if(![htmlPaths count]) {
    [unzip release];
    [pool release];
    return noErr;
  }


  // Combine the data of HTML files.
  NSMutableDictionary *attachments = [NSMutableDictionary dictionary];
  NSMutableData *htmlData = [NSMutableData data];
  for(NSString *htmlPath in htmlPaths) {
    NSData *rawHtmlData = [unzip dataWithContentsOfFile:htmlPath];
    xmlDoc = [[NSXMLDocument alloc] initWithData:rawHtmlData
                                         options:NSXMLDocumentTidyXML
                                           error:NULL];
    if(!xmlDoc) continue;

    if(maximumNumberOfLoadingImage != 0) {
      // Rewrite the paths of embedded image files and css files,
      // and then store the data to an attachment dictionary,
      xpath = @"//img/@src"
        @"|//*[local-name()='svg']/*[local-name()='image']/@*[local-name()='href']"
        @"|//*[local-name()='svg']/*[local-name()='image']/@href"
        @"|//*[local-name()='svg']/image/@*[local-name()='href']"
        @"|//*[local-name()='svg']/image/@href"
        @"|//svg/*[local-name()='image']/@*[local-name()='href']"
        @"|//svg/*[local-name()='image']/@href"
        @"|//svg/image/@*[local-name()='href']"
        @"|//svg/image/@href"
        @"|//head/link/@href"
      ;
      nodes = [xmlDoc nodesForXPath:xpath error:NULL];
      NSString *htmlBasePath = [htmlPath stringByDeletingLastPathComponent];
      NSUInteger numberOfImage = 0;
      for(NSXMLNode *node in nodes) {
        if(QLPreviewRequestIsCancelled(preview)) {
          [xmlDoc release];
          [unzip release];
          [pool release];
          return noErr;
        }

        NSString *attachmentPath = nil;
        NSString *srcValue = [[node stringValue] stringByTrimmingCharactersInSet:setForTrim];
        srcValue = [srcValue stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        if([srcValue isAbsolutePath]) attachmentPath = [srcValue substringFromIndex:1];
        else attachmentPath = [htmlBasePath stringByAppendingPathComponent:srcValue];

        // Resolve refarences to the parent directory.
        // Append "/" to top of the path,
        // because stringByStandardizingPath can't resolve relative path.
        attachmentPath = [@"/" stringByAppendingPathComponent:attachmentPath];
        attachmentPath = [attachmentPath stringByStandardizingPath];
        attachmentPath = [attachmentPath substringFromIndex:1];

        NSData *attachmentData = [unzip dataWithContentsOfFile:attachmentPath];
        if(!attachmentData) continue;

        [node setStringValue:[@"cid:" stringByAppendingString:attachmentPath]];

        NSString *key = (NSString *)kQLPreviewPropertyAttachmentDataKey;
        NSDictionary *attachment = [NSDictionary dictionaryWithObject:attachmentData
                                                               forKey:key];
        [attachments setObject:attachment forKey:attachmentPath];

        if(maximumNumberOfLoadingImage != kLoadAllFiles &&
           ++numberOfImage >= maximumNumberOfLoadingImage) break;
      }
    }

    [htmlData appendData:[xmlDoc XMLData]];
    [xmlDoc release];
  }

  NSDictionary *properties = [NSDictionary dictionaryWithObjectsAndKeys:
                              @"text/html",
                              (NSString *)kQLPreviewPropertyMIMETypeKey,
                              @"UTF-8",
                              (NSString *)kQLPreviewPropertyTextEncodingNameKey,
                              attachments,
                              (NSString *)kQLPreviewPropertyAttachmentsKey,
                              nil];
  QLPreviewRequestSetDataRepresentation(preview,
                                        (CFDataRef)htmlData,
                                        kUTTypeHTML,
                                        (CFDictionaryRef)properties);

  [unzip release];
  [pool release];

  return noErr;
}

void CancelPreviewGeneration(void* thisInterface, QLPreviewRequestRef preview)
{
  // implement only if supported
}
