//
//  GNJUnZip.m
//  EPUBImporter
//
//  Created by Genji on 11/07/12.
//  Copyright 2011 Genji App. All rights reserved.
//

#import "GNJUnZip.h"

@implementation GNJUnZip

@synthesize path = path_;

/**
 * Initializes and returns an unzip object.
 * This object opens an unzFile object that
 * represents the zip file specified by a given path.
 *
 * @param path The absolute path of the zip file from which to opens.
 */
- (id)initWithZipFile:(NSString *)path
{
  if((self = [self init]) != nil) {
    unzipFile_ = unzOpen([path fileSystemRepresentation]);
    if(unzipFile_ == NULL) {
      NSLog(@"error: cannot open zip archive specified by path '%@'", path);
      return nil;
    }
    path_ = [path copy];
  }

  return self;
}

/**
 * Deallocates the memory occupied by the receiver,
 * and closes unzFile object.
 */
- (void)dealloc
{
  if(unzipFile_) unzClose(unzipFile_);
  [path_ release];

  [super dealloc];
}

/**
 * Returns an array containing the files' paths in zip archive.
 *
 * @return an array containing the files' paths in zip archive.
 */
- (NSArray *)items
{
  if(!unzipFile_) {
    NSLog(@"error: unzFile is not opened yet");
    return nil;
  }

  if(unzGoToFirstFile(unzipFile_) != UNZ_OK) {
    NSLog(@"error: cannot go to first file in zipfile");
    return nil;
  }

  NSMutableArray *itemsArray = [NSMutableArray array];
  do {
    char rawFilename[512];
    unz_file_info fileInfo;
    unzGetCurrentFileInfo(unzipFile_, &fileInfo,
                          rawFilename, sizeof(rawFilename),
                          NULL, 0, NULL, 0);
    NSString *filename = [NSString stringWithCString:rawFilename
                                            encoding:NSUTF8StringEncoding];
    [itemsArray addObject:filename];
  } while(unzGoToNextFile(unzipFile_) != UNZ_END_OF_LIST_OF_FILE);

  return itemsArray;
}

/**
 * Creates and returns a data object by reading every byte
 * from the file specified by a given path in zip archive.
 *
 * @param path The path of the file from which to read data.
 * @return A data object by reading every byte from the file specified by path.
 *         Returns nil if the data object could not be created.
 */
- (NSData *)dataWithContentsOfFile:(NSString *)path
{
  if(!unzipFile_) {
    NSLog(@"error: unzFile is not opened yet");
    return nil;
  }

  const char *rawFilename = [path fileSystemRepresentation];
  if(unzLocateFile(unzipFile_, rawFilename, 0) != UNZ_OK) {
    NSLog(@"error: cannot locate file '%@'", path);
    return nil;
  }

  if(unzOpenCurrentFile(unzipFile_) != UNZ_OK) {
    NSLog(@"error: cannot open '%@'", path);
    return nil;
  }

  NSMutableData *data = [NSMutableData data];
  unsigned int bufferSize = 1024;
  void *buffer = (void *)malloc(bufferSize);
  while(1) {
    int results = unzReadCurrentFile(unzipFile_, buffer, bufferSize);
    if(results < 0) {
      NSLog(@"error: occurred reading data error (error code: %d)", results);
      unzCloseCurrentFile(unzipFile_);
      return nil;
    }
    else if(results == 0) break;
    [data appendBytes:buffer length:results];
  }
  unzCloseCurrentFile(unzipFile_);
  free(buffer);

  return data;
}

@end
