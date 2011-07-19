#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <QuickLook/QuickLook.h>
#import "Cocoa/Cocoa.h"
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
    [xmlDoc release];
    [unzip release];
    [pool release];
    return noErr;
  }

  NSString *opfPath = [[nodes objectAtIndex:0] stringValue];
  [xmlDoc release];


  // Get the path of HTML files
  xmlData = [unzip dataWithContentsOfFile:opfPath];
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
    [xmlDoc release];
    [unzip release];
    [pool release];
    return noErr;
  }

  NSMutableDictionary *manifest = [NSMutableDictionary dictionary];
  for(NSXMLElement *elem in nodes) {
    NSXMLNode *idNode = [elem attributeForName:@"id"];
    NSXMLNode *hrefNode = [elem attributeForName:@"href"];
    [manifest setObject:[hrefNode stringValue] forKey:[idNode stringValue]];
  }

  xpath = @"/package/spine/itemref/@idref";
  nodes = [xmlDoc nodesForXPath:xpath error:NULL];
  if(![nodes count]) {
    [xmlDoc release];
    [unzip release];
    [pool release];
    return noErr;
  }

  NSUInteger numberOfHTML = 0;
  NSMutableArray *htmlPaths = [NSMutableArray array];
  for(NSXMLNode *node in nodes) {
    NSString *idref = [node stringValue];
    NSString *opfBasePath = [opfPath stringByDeletingLastPathComponent];
    NSString *htmlPath = [opfBasePath stringByAppendingPathComponent:
                          [manifest objectForKey:idref]];
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
      // Rewrite the path of images,
      // store the data of the attachment images to dictionary,
      xpath = @"//img/@src";
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

        NSString *thePath = [node stringValue];
        NSString *attachmentPath = [htmlBasePath
                                    stringByAppendingPathComponent:thePath];

        // Resolve refarences to the parent directory.
        // Append "/" to top of the path,
        // because stringByStandardizingPath can't resolve relative path.
        attachmentPath = [@"/" stringByAppendingPathComponent:attachmentPath];
        attachmentPath = [attachmentPath stringByStandardizingPath];
        attachmentPath = [attachmentPath substringFromIndex:1];

        NSData *attachmentData = [unzip dataWithContentsOfFile:attachmentPath];
        if(!attachmentData) continue;

        [node setStringValue:[@"cid:" stringByAppendingString:attachmentPath]];

        NSDictionary *attachment;
        attachment = [NSDictionary
                      dictionaryWithObject:attachmentData
                      forKey:(NSString *)kQLPreviewPropertyAttachmentDataKey];
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
