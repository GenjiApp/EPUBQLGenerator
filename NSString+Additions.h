//
//  NSString+Additions.h
//  EPUBQLGenerator
//
//  Created by Genji on 2013/03/10.
//  Copyright 2013 Genji App. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSString (Additions)

/**
 * Returns a new string made from the receiver by forcibly resolving all symbolic links
 * and standardizing path. stringByResolvingSymlinksInPath doesn't resolve references
 * to parent directory, but this method forcibly resolves them by prepend "/" to the path,
 * then removes "/" from string and returns it.
 **/
- (NSString *)stringByForciblyResolvingSymlinksInPath;

@end
