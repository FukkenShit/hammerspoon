//
//  HSStreamDeckDevice.h
//  Hammerspoon
//
//  Created by Chris Jones on 06/09/2017.
//  Copyright © 2017 Hammerspoon. All rights reserved.
//

@import Foundation;
@import Cocoa;
@import IOKit;
@import IOKit.hid;
@import LuaSkin;

#import "NSImage+BMP.h"
#import "NSImage+JPEG.h"
#import "NSImage+Rotated.h"
#import "NSImage+Flipped.h"

#import "streamdeck.h"


typedef enum : NSUInteger {
    STREAMDECK_CODEC_UNKNOWN,
    STREAMDECK_CODEC_BMP,
    STREAMDECK_CODEC_JPEG,
} HSStreamDeckImageCodec;

@interface HSStreamDeckDevice : NSObject {
    NSString *serialNumberCache;
}
@property (nonatomic) IOHIDDeviceRef device;
@property (nonatomic) id manager;
@property (nonatomic) int selfRefCount;

@property (nonatomic) int buttonCallbackRef;
@property (nonatomic) int encoderCallbackRef;
@property (nonatomic) int screenCallbackRef;

@property (nonatomic) BOOL isValid;
@property (nonatomic) LSGCCanary lsCanary;

@property (nonatomic) NSString *deckType;
@property (nonatomic, readonly, getter=getKeyCount) int keyCount;
@property (nonatomic) int keyColumns;
@property (nonatomic) int keyRows;
@property (nonatomic) int imageWidth;
@property (nonatomic) int imageHeight;
@property (nonatomic) int imageWidthFullScreen;
@property (nonatomic) int imageHeightFullScreen;

@property (nonatomic, readonly, getter=getEncoderCount) int encoderCount;
@property (nonatomic) int encoderColumns;
@property (nonatomic) int encoderRows;

@property (nonatomic) int lcdStripWidth;
@property (nonatomic) int lcdStripHeight;

@property (nonatomic) HSStreamDeckImageCodec imageCodec;
@property (nonatomic) BOOL imageFlipX;
@property (nonatomic) BOOL imageFlipY;
@property (nonatomic) int imageAngle;
@property (nonatomic) int simpleReportLength;
@property (nonatomic) int reportLength;
@property (nonatomic) int reportHeaderLength;

@property (nonatomic) int lcdReportLength;
@property (nonatomic) int lcdReportHeaderLength;

@property (nonatomic) int dataKeyOffset;
@property (nonatomic) int dataEncoderOffset;
@property (nonatomic) NSUInteger firmwareReadOffset;
@property (nonatomic) NSUInteger serialNumberReadOffset;
@property (nonatomic) NSData *resetCommand;
@property (nonatomic) NSData *setBrightnessCommand;
@property (nonatomic) NSUInteger serialNumberCommand;
@property (nonatomic) NSUInteger firmwareVersionCommand;

@property (nonatomic) NSMutableArray *buttonStateCache;
@property (nonatomic) NSMutableArray *encoderButtonStateCache;

@property (nonatomic, readonly, getter=getSerialNumber) NSString *serialNumber;


- (id)initWithDevice:(IOHIDDeviceRef)device manager:(id)manager;
- (void)invalidate;
- (void)initialiseCaches;

- (IOReturn)deviceWriteSimpleReport:(NSData *)command;
- (IOReturn)deviceWrite:(NSData *)report;
- (void)deviceWriteImage:(NSData *)data button:(int)button;
- (void)deviceV2WriteImage:(NSData *)data button:(int)button;
- (void)deviceV2WriteImageFullScreen:(NSData *)data;
- (NSData *)deviceRead:(int)resultLength reportID:(CFIndex)reportID readOffset:(NSUInteger)readOffset;

- (int)transformKeyIndex:(int)sourceKey;

- (void)deviceDidSendInput:(NSArray*)newButtonStates;
- (void)deviceDidSendEncoderInput:(NSArray*)newEncoderButtonStates;
- (void)deviceDidSendEncoderTurnWithButton:(NSNumber*)button turningLeft:(BOOL)turningLeft;

- (BOOL)setBrightness:(int)brightness;
- (void)reset;

- (NSString *)cacheSerialNumber;
- (NSString *)firmwareVersion;
- (int)getKeyCount;

- (void)clearImage:(int)button;
- (void)setColor:(NSColor*)color forButton:(int)button;
- (void)setImage:(NSImage*)image forButton:(int)button;

- (void)clearImageFullScreen;
- (void)setColorFullScreen:(NSColor*)color;
- (void)setImageFullScreen:(NSImage*)image;

- (void)setLCDImage:(NSImage*)image forEncoder:(int)encoder;

- (void)deviceDidSendScreenTouch:(NSString*)eventType startX:(int)startX startY:(int)startY endX:(int)endX endY:(int)endY;

@end
