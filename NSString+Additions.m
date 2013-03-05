//
//  NSString+Additions.m
//  EPUBQLGenerator
//
//  Created by Genji on 2013/03/10.
//  Copyright 2013 Genji App. All rights reserved.
//

#import "NSString+Additions.h"

@implementation NSString (Additions)

- (NSString *)stringByForciblyResolvingSymlinksInPath
{
  if([self isAbsolutePath]) return [self stringByResolvingSymlinksInPath];

  NSString *absolutePath = [@"/" stringByAppendingPathComponent:self];
  NSString *standardizedPath = [absolutePath stringByResolvingSymlinksInPath];
  return [standardizedPath substringFromIndex:1];
}

@end
