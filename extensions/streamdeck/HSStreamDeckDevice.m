//
//  HSStreamDeckDevice.m
//  Hammerspoon
//
//  Created by Chris Jones on 06/09/2017.
//  Copyright © 2017 Hammerspoon. All rights reserved.
//

#import "HSStreamDeckDevice.h"

@interface HSStreamDeckDevice ()
@property (nonatomic, copy) NSString *serialNumber;
@end

@implementation HSStreamDeckDevice
- (id)initWithDevice:(IOHIDDeviceRef)device manager:(id)manager {
    self = [super init];
    if (self) {
        self.device = device;
        self.isValid = YES;
        self.manager = manager;
        
        self.buttonCallbackRef = LUA_NOREF;
        self.encoderCallbackRef = LUA_NOREF;
        self.screenCallbackRef = LUA_NOREF;
        
        self.selfRefCount = 0;

        self.buttonStateCache = [[NSMutableArray alloc] init];
        self.encoderButtonStateCache = [[NSMutableArray alloc] init];

        // These defaults are not necessary, all base classes will override them, but if we miss something, these are chosen to try and provoke a crash where possible, so we notice the lack of an override.
        self.imageCodec = STREAMDECK_CODEC_UNKNOWN;
        self.deckType = @"Unknown";
        self.keyColumns = -1;
        self.keyRows = -1;
        self.imageFlipX = NO;
        self.imageFlipY = NO;
        self.imageAngle = 0;
        self.simpleReportLength = 0;
        self.reportLength = 0;
        self.reportHeaderLength = 0;
        
        self.lcdReportLength = 0;
        self.lcdReportHeaderLength = 0;

        self.encoderColumns = 0;
        self.encoderRows = 0;
        
        self.lcdStripWidth = 0;
        self.lcdStripHeight = 0;
        
        self.dataKeyOffset = 0;
        self.dataEncoderOffset = 0;
        
        self.resetCommand = nil;
        self.setBrightnessCommand = nil;
        self.serialNumberCommand = 0;
        self.firmwareVersionCommand = 0;

        self.firmwareReadOffset = 0;
        self.serialNumberReadOffset = 0;

        serialNumberCache = nil;
        //NSLog(@"Added new Stream Deck device %p with IOKit device %p from manager %p", (__bridge void *)self, (void*)self.device, (__bridge void *)self.manager);
    }
    return self;
}

- (void)invalidate {
    self.isValid = NO;
}

- (void)initialiseCaches {
    for (int i = 0; i <= self.keyCount; i++) {
        [self.buttonStateCache setObject:@0 atIndexedSubscript:i];
    }
    
    for (int i = 0; i <= self.encoderCount; i++) {
        [self.encoderButtonStateCache setObject:@0 atIndexedSubscript:i];
    }
    
    [self cacheSerialNumber];
}

- (IOReturn)deviceWriteSimpleReport:(NSData *)command {
    if (self.simpleReportLength == 0) {
        [LuaSkin logError:@"Initialising Stream Deck device with no simple report length defined"];
        return kIOReturnInternalError;
    }
    NSMutableData *reportData = [NSMutableData dataWithLength:self.simpleReportLength];
    [reportData replaceBytesInRange:NSMakeRange(0, command.length) withBytes:command.bytes];
    return [self deviceWrite:reportData];
}

- (IOReturn)deviceWrite:(NSData *)report {
    const uint8_t *rawBytes = (const uint8_t*)report.bytes;
    return IOHIDDeviceSetReport(self.device, kIOHIDReportTypeFeature, rawBytes[0], rawBytes, report.length);
}

- (NSData *)deviceRead:(int)resultLength reportID:(CFIndex)reportID readOffset:(NSUInteger)readOffset {
    CFIndex reportLength = resultLength + readOffset;
    uint8_t *report = malloc(reportLength);

    //NSLog(@"deviceRead: expecting resultLength %d, calculated report length %ld", resultLength, (long)reportLength);

    IOHIDDeviceGetReport(self.device, kIOHIDReportTypeFeature, reportID, report, &reportLength);
    char *c_data = (char *)(report + readOffset);
    NSData *dataRaw = [NSData dataWithBytes:c_data length:resultLength];
    free(report);

    NSMutableData *data = [NSMutableData dataWithLength:0];
    [dataRaw enumerateByteRangesUsingBlock:^(const void * _Nonnull bytes, NSRange byteRange, BOOL * _Nonnull stop) {
        NSUInteger copyLength = byteRange.length;
        for (NSUInteger i = 0; i < byteRange.length; i++) {
            if (((const uint8_t*)bytes)[i] == 0x00) {
                copyLength = i + 1;
                break;
            }
        }
        [data appendBytes:bytes length:copyLength-1];
    }];

    return data;
}

- (int)transformKeyIndex:(int)sourceKey {
    //NSLog(@"transformKeyIndex: returning %d unmodified", sourceKey);
    return sourceKey;
}

- (void)deviceDidSendInput:(NSArray*)newButtonStates {
    //NSLog(@"Got an input event from device: %p: button:%@ isDown:%@", (__bridge void*)self, button, isDown);

    if (!self.isValid) {
        return;
    }

    LuaSkin *skin = [LuaSkin sharedWithState:NULL];
    _lua_stackguard_entry(skin.L);

    if (![skin checkGCCanary:self.lsCanary]) {
        _lua_stackguard_exit(skin.L);
        return;
    }

    if (self.buttonCallbackRef == LUA_NOREF || self.buttonCallbackRef == LUA_REFNIL) {
        [skin logError:@"hs.streamdeck received a button input, but no callback has been set. See hs.streamdeck:buttonCallback()"];
        return;
    }

    //NSLog(@"buttonStateCache: %@", self.buttonStateCache);
    //NSLog(@"newButtonStates: %@", newButtonStates);

    for (int button=1; button <= self.keyCount; button++) {
        if (![self.buttonStateCache[button] isEqual:newButtonStates[button]]) {
            [skin pushLuaRef:streamDeckRefTable ref:self.buttonCallbackRef];
            [skin pushNSObject:self];
            lua_pushinteger(skin.L, button);
            lua_pushboolean(skin.L, ((NSNumber*)(newButtonStates[button])).boolValue);
            [skin protectedCallAndError:@"hs.streamdeck:buttonCallback" nargs:3 nresults:0];
            self.buttonStateCache[button] = newButtonStates[button];
        }
    }

    _lua_stackguard_exit(skin.L);
}

- (void)deviceDidSendEncoderInput:(NSArray*)newPressEncoderStates {
    
    if (!self.isValid) {
        return;
    }

    LuaSkin *skin = [LuaSkin sharedWithState:NULL];
    _lua_stackguard_entry(skin.L);

    if (![skin checkGCCanary:self.lsCanary]) {
        _lua_stackguard_exit(skin.L);
        return;
    }

    if (self.encoderCallbackRef == LUA_NOREF || self.encoderCallbackRef == LUA_REFNIL) {
        [skin logError:@"hs.streamdeck received an encoder button input, but no callback has been set. See hs.streamdeck:encoderCallback()"];
        return;
    }

    for (int button=1; button <= self.encoderCount; button++) {
        if (![self.encoderButtonStateCache[button] isEqual:newPressEncoderStates[button]]) {
            [skin pushLuaRef:streamDeckRefTable ref:self.encoderCallbackRef];
            [skin pushNSObject:self];
            lua_pushinteger(skin.L, button);
            lua_pushboolean(skin.L, ((NSNumber*)(newPressEncoderStates[button])).boolValue);
            lua_pushboolean(skin.L, false);
            lua_pushboolean(skin.L, false);
            [skin protectedCallAndError:@"hs.streamdeck:encoderCallback" nargs:5 nresults:0];
            self.encoderButtonStateCache[button] = newPressEncoderStates[button];
        }
        
    }

    _lua_stackguard_exit(skin.L);
}

- (void)deviceDidSendEncoderTurnWithButton:(NSNumber*)button turningLeft:(BOOL)turningLeft {
    
    if (!self.isValid) {
        return;
    }

    LuaSkin *skin = [LuaSkin sharedWithState:NULL];
    _lua_stackguard_entry(skin.L);

    if (![skin checkGCCanary:self.lsCanary]) {
        _lua_stackguard_exit(skin.L);
        return;
    }

    if (self.encoderCallbackRef == LUA_NOREF || self.encoderCallbackRef == LUA_REFNIL) {
        [skin logError:@"hs.streamdeck received an encoder button input, but no callback has been set. See hs.streamdeck:encoderCallback()"];
        return;
    }

    [skin pushLuaRef:streamDeckRefTable ref:self.encoderCallbackRef];
    [skin pushNSObject:self];
    lua_pushinteger(skin.L, [button intValue]);
    lua_pushboolean(skin.L, false);
    lua_pushboolean(skin.L, turningLeft);
    lua_pushboolean(skin.L, !turningLeft);
    [skin protectedCallAndError:@"hs.streamdeck:encoderCallback" nargs:5 nresults:0];

    _lua_stackguard_exit(skin.L);
}

- (void)deviceDidSendScreenTouch:(NSString*)eventType startX:(int)startX startY:(int)startY endX:(int)endX endY:(int)endY {
    
    if (!self.isValid) {
        return;
    }

    LuaSkin *skin = [LuaSkin sharedWithState:NULL];
    _lua_stackguard_entry(skin.L);

    if (![skin checkGCCanary:self.lsCanary]) {
        _lua_stackguard_exit(skin.L);
        return;
    }

    if (self.screenCallbackRef == LUA_NOREF || self.screenCallbackRef == LUA_REFNIL) {
        [skin logError:@"hs.streamdeck received an screen input, but no callback has been set. See hs.streamdeck:screenCallback()"];
        return;
    }
    
    [skin pushLuaRef:streamDeckRefTable ref:self.screenCallbackRef];
    [skin pushNSObject:self];
    [skin pushNSObject:eventType];
    lua_pushinteger(skin.L, startX);
    lua_pushinteger(skin.L, startY);
    lua_pushinteger(skin.L, endX);
    lua_pushinteger(skin.L, endY);
    [skin protectedCallAndError:@"hs.streamdeck:screenCallback" nargs:6 nresults:0];

    _lua_stackguard_exit(skin.L);
}

- (BOOL)setBrightness:(int)brightness {
    if (!self.isValid) {
        return NO;
    }

    if (!self.setBrightnessCommand) {
        NSException *exception = [NSException exceptionWithName:@"HSStreamDeckDeviceUnimplemented"
                                                         reason:@"setBrightness method not implemented"
                                                       userInfo:nil];
        [exception raise];
        return NO;
    }

    NSMutableData *brightnessCommand = [self.setBrightnessCommand mutableCopy];
    [brightnessCommand replaceBytesInRange:NSMakeRange(self.setBrightnessCommand.length - 1, 1) withBytes:&brightness];
    IOReturn res = [self deviceWriteSimpleReport:brightnessCommand];

    return res == kIOReturnSuccess;
}

- (void)reset {
    if (!self.isValid) {
        return;
    }

    if (!self.resetCommand) {
        NSException *exception = [NSException exceptionWithName:@"HSStreamDeckDeviceUnimplemented"
                                                         reason:@"resetCommand bytes not set, or reset method not overridden"
                                                       userInfo:nil];
        [exception raise];
        return;
    }

    IOReturn res = [self deviceWriteSimpleReport:self.resetCommand];
    if (res != kIOReturnSuccess) {
        NSLog(@"hs.streamdeck:reset() failed on %@ (%@)", self.deckType, self.serialNumber);
    }


}

- (NSString*)getSerialNumber {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdirect-ivar-access"

    if (!serialNumberCache) {
        // This shouldn't be necessary, since we cache the serial number when the device is initialised, but just in case
        serialNumberCache = [self cacheSerialNumber];
    }

    return serialNumberCache;
#pragma clang diagnostic pop
}

- (NSString *)cacheSerialNumber {
    if (!self.isValid) {
        return nil;
    }

    if (self.serialNumberCommand == 0) {
        NSException *exception = [NSException exceptionWithName:@"HSStreamDeckDeviceUnimplemented"
                                                         reason:@"serialNumberCommand not set, or cacheSerialNumber method not overridden"
                                                       userInfo:nil];
        [exception raise];
        return nil;
    }

    NSData *serialNumberData = [self deviceRead:self.simpleReportLength reportID:self.serialNumberCommand readOffset:self.serialNumberReadOffset];

    NSString *serialNumber = [[NSString alloc] initWithData:serialNumberData
                                                   encoding:NSUTF8StringEncoding];
    return serialNumber;
}

- (NSString*)firmwareVersion {
    if (!self.isValid) {
        return nil;
    }

    if (self.firmwareVersionCommand == 0) {
        NSException *exception = [NSException exceptionWithName:@"HSStreamDeckDeviceUnimplemented"
                                                         reason:@"firmwareVersionCOmmand not set, or firmwareVersion method not implemented"
                                                       userInfo:nil];
        [exception raise];
    }

    NSString *firmwareVersion = [[NSString alloc] initWithData:[self deviceRead:self.simpleReportLength reportID:self.firmwareVersionCommand readOffset:self.firmwareReadOffset]
                                                      encoding:NSUTF8StringEncoding];
    return firmwareVersion;
}

- (int)getKeyCount {
    return self.keyColumns * self.keyRows;
}

- (int)getEncoderCount {
    return self.encoderColumns * self.encoderRows;
}

- (void)clearImage:(int)button {
    [self setColor:[NSColor blackColor] forButton:button];
}

- (void)setColor:(NSColor *)color forButton:(int)button {
    if (!self.isValid) {
        return;
    }

    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(self.imageWidth, self.imageHeight)];
    [image lockFocus];
    [color drawSwatchInRect:NSMakeRect(0, 0, self.imageWidth, self.imageHeight)];
    [image unlockFocus];
    [self setImage:image forButton:button];
}

- (void)setImage:(NSImage *)image forButton:(int)button {
    if (!self.isValid) {
        return;
    }

    NSImage *renderImage;

    // Unconditionally resize the image
    NSImage *sourceImage = [image copy];
    NSSize newSize = NSMakeSize(self.imageWidth, self.imageHeight);
    renderImage = [[NSImage alloc] initWithSize: newSize];
    [renderImage lockFocus];
    [sourceImage setSize: newSize];
    [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
    [sourceImage drawAtPoint:NSZeroPoint fromRect:CGRectMake(0, 0, newSize.width, newSize.height) operation:NSCompositingOperationCopy fraction:1.0];
    [renderImage unlockFocus];

    if (![image isValid]) {
        [LuaSkin logError:@"image is invalid"];
    }
    if (![renderImage isValid]) {
        [LuaSkin logError:@"Invalid image passed to hs.streamdeck:setImage() (renderImage)"];
    //    return;
    }

    // Both of these functions are no-ops if there are no rotations or flips required, so we'll call them unconditionally
    renderImage = [renderImage imageRotated:self.imageAngle];
    renderImage = [renderImage flipImage:self.imageFlipX vert:self.imageFlipY];

    NSData *data = nil;

    switch (self.imageCodec) {
        case STREAMDECK_CODEC_BMP:
            data = [renderImage bmpData];
            break;

        case STREAMDECK_CODEC_JPEG:
            data = [renderImage jpegData];
            break;

        case STREAMDECK_CODEC_UNKNOWN:
            [LuaSkin logError:@"Unknown image codec for hs.streamdeck device"];
            break;
    }

    // Writing the image to hardware is a device-specific operation, so hand it off to our subclasses
    [self deviceWriteImage:data button:[self transformKeyIndex:button]];

}

- (void)deviceWriteImage:(NSData *)data button:(int)button {
    NSException *exception = [NSException exceptionWithName:@"HSStreamDeckDeviceUnimplemented"
                                                     reason:@"deviceWriteImage method not implemented"
                                                   userInfo:nil];
    [exception raise];
}

- (void)deviceV2WriteImage:(NSData *)data button:(int)button {
    uint8_t reportHeader[] = {0x02,   // Report ID
                             0x07,   // Unknown (always seems to be 7)
                             button - 1, // Deck button to set
                             0x00,   // Final page bool
                             0x00,   // Some kind of encoding of the length of the current page
                             0x00,   // Some other kind of encoding of the current page length
                             0x00,   // Some kind of encoding of the page number
                             0x00    // Some other kind of encoding of the page number
                            };

    // The v2 Stream Decks needs images sent in slices no more than 1016 bytes + the report header
    int maxPayloadLength = self.reportLength - self.reportHeaderLength;

    int bytesRemaining = (int)data.length;
    int bytesSent = 0;
    int pageNumber = 0;
    const uint8_t *imageBuf = data.bytes;

    IOReturn result;

    while (bytesRemaining > 0) {
        int thisPageLength = MIN(bytesRemaining, maxPayloadLength);
        bytesSent = pageNumber * maxPayloadLength;

        // Set our current page number
        reportHeader[6] = pageNumber & 0xFF;
        reportHeader[7] = pageNumber >> 8;

        // Set our current page length
        reportHeader[4] = thisPageLength & 0xFF;
        reportHeader[5] = thisPageLength >> 8;

        // Set if we're the last page of data
        if (bytesRemaining <= maxPayloadLength) reportHeader[3] = 1;

        NSMutableData *report = [NSMutableData dataWithLength:self.reportLength];
        [report replaceBytesInRange:NSMakeRange(0, self.reportHeaderLength)
                          withBytes:reportHeader];
        [report replaceBytesInRange:NSMakeRange(self.reportHeaderLength, thisPageLength)
                          withBytes:imageBuf+bytesSent
                             length:thisPageLength];

        result = IOHIDDeviceSetReport(self.device,
                                      kIOHIDReportTypeOutput,
                                      reportHeader[0],
                                      report.bytes,
                                      (int)report.length);
        if (result != kIOReturnSuccess) {
            NSLog(@"WARNING: writing an image with hs.streamdeck encountered a failure on page %d: %d", pageNumber, result);
        }

        bytesRemaining = bytesRemaining - thisPageLength;
        pageNumber++;
    }
}

- (void)clearImageFullScreen {
    [self setColorFullScreen:[NSColor blackColor]];
}

- (void)setColorFullScreen:(NSColor *)color {
    if (!self.isValid) {
        return;
    }

    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(self.imageWidthFullScreen, self.imageHeightFullScreen)];
    [image lockFocus];
    [color drawSwatchInRect:NSMakeRect(0, 0, self.imageWidthFullScreen, self.imageHeightFullScreen)];
    [image unlockFocus];
    [self setImageFullScreen:image];
}

- (void)setImageFullScreen:(NSImage *)image {
    if (!self.isValid) {
        return;
    }

    NSImage *renderImage;

    // Unconditionally resize the image
    NSImage *sourceImage = [image copy];
    NSSize newSize = NSMakeSize(self.imageWidthFullScreen, self.imageHeightFullScreen);
    renderImage = [[NSImage alloc] initWithSize: newSize];
    [renderImage lockFocus];
    [sourceImage setSize: newSize];
    [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
    [sourceImage drawAtPoint:NSZeroPoint fromRect:(CGRect){ CGPointZero, newSize } operation:NSCompositingOperationCopy fraction:1.0];
    [renderImage unlockFocus];

    if (![image isValid]) {
        [LuaSkin logError:@"image is invalid"];
    }
    if (![renderImage isValid]) {
        [LuaSkin logError:@"Invalid image passed to hs.streamdeck:setImage() (renderImage)"];
    //    return;
    }

    // Both of these functions are no-ops if there are no rotations or flips required, so we'll call them unconditionally
    renderImage = [renderImage imageRotated:self.imageAngle];
    renderImage = [renderImage flipImage:self.imageFlipX vert:self.imageFlipY];

    NSData *data = nil;

    switch (self.imageCodec) {
        case STREAMDECK_CODEC_BMP:
            data = [renderImage bmpData];
            break;

        case STREAMDECK_CODEC_JPEG:
            data = [renderImage jpegData];
            break;

        case STREAMDECK_CODEC_UNKNOWN:
            [LuaSkin logError:@"Unknown image codec for hs.streamdeck device"];
            break;
    }

    // Writing the image to hardware is a device-specific operation, so hand it off to our subclasses
    [self deviceWriteImageFullScreen:data];

}

- (void)deviceWriteImageFullScreen:(NSData *)data {
    NSException *exception = [NSException exceptionWithName:@"HSStreamDeckDeviceUnimplemented"
                                                     reason:@"deviceWriteImage method not implemented"
                                                   userInfo:nil];
    [exception raise];
}

- (void)deviceV2WriteImageFullScreen:(NSData *)data {
    uint8_t reportHeader[] = {0x02,  // Report ID
                             0x08,   // Always 8
                             0,      // Unused
                             0x00,   // Final page bool
                             0x00,   // Some kind of encoding of the length of the current page
                             0x00,   // Some other kind of encoding of the current page length
                             0x00,   // Some kind of encoding of the page number
                             0x00    // Some other kind of encoding of the page number
                            };

    // The v2 Stream Decks needs images sent in slices no more than 1016 bytes + the report header
    int maxPayloadLength = self.reportLength - self.reportHeaderLength;

    int bytesRemaining = (int)data.length;
    int bytesSent = 0;
    int pageNumber = 0;
    const uint8_t *imageBuf = data.bytes;

    IOReturn result;

    while (bytesRemaining > 0) {
        int thisPageLength = MIN(bytesRemaining, maxPayloadLength);
        bytesSent = pageNumber * maxPayloadLength;

        // Set our current page number
        reportHeader[6] = pageNumber & 0xFF;
        reportHeader[7] = pageNumber >> 8;

        // Set our current page length
        reportHeader[4] = thisPageLength & 0xFF;
        reportHeader[5] = thisPageLength >> 8;

        // Set if we're the last page of data
        if (bytesRemaining <= maxPayloadLength) reportHeader[3] = 1;

        NSMutableData *report = [NSMutableData dataWithLength:self.reportLength];
        [report replaceBytesInRange:NSMakeRange(0, self.reportHeaderLength)
                          withBytes:reportHeader];
        [report replaceBytesInRange:NSMakeRange(self.reportHeaderLength, thisPageLength)
                          withBytes:imageBuf+bytesSent
                             length:thisPageLength];

        result = IOHIDDeviceSetReport(self.device,
                                      kIOHIDReportTypeOutput,
                                      reportHeader[0],
                                      report.bytes,
                                      (int)report.length);
        if (result != kIOReturnSuccess) {
            NSLog(@"WARNING: writing an image with hs.streamdeck encountered a failure on page %d: %d", pageNumber, result);
        }

        bytesRemaining = bytesRemaining - thisPageLength;
        pageNumber++;
    }
}


- (void)setLCDImage:(NSImage *)image forEncoder:(int)encoder {
    if (!self.isValid) {
        return;
    }

    NSImage *renderImage;

    // Unconditionally resize the image
    NSImage *sourceImage = [image copy];
    int encoderWidth = self.lcdStripWidth / self.encoderColumns;
    NSSize newSize = NSMakeSize(encoderWidth, self.lcdStripHeight);
    renderImage = [[NSImage alloc] initWithSize: newSize];
    [renderImage lockFocus];
    [sourceImage setSize: newSize];
    [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
    [sourceImage drawAtPoint:NSZeroPoint fromRect:CGRectMake(0, 0, newSize.width, newSize.height) operation:NSCompositingOperationCopy fraction:1.0];
    [renderImage unlockFocus];

    if (![image isValid]) {
        [LuaSkin logError:@"image is invalid"];
    }
    if (![renderImage isValid]) {
        [LuaSkin logError:@"Invalid image passed to hs.streamdeck:setLCDImage() (renderImage)"];
    //    return;
    }

    // Both of these functions are no-ops if there are no rotations or flips required, so we'll call them unconditionally
    renderImage = [renderImage imageRotated:self.imageAngle];
    renderImage = [renderImage flipImage:self.imageFlipX vert:self.imageFlipY];

    NSData *data = nil;

    switch (self.imageCodec) {
        case STREAMDECK_CODEC_BMP:
            data = [renderImage bmpData];
            break;

        case STREAMDECK_CODEC_JPEG:
            data = [renderImage jpegData];
            break;

        case STREAMDECK_CODEC_UNKNOWN:
            [LuaSkin logError:@"Unknown image codec for hs.streamdeck device"];
            break;
    }

    // Writing the image to hardware is a device-specific operation, so hand it off to our subclasses
    [self deviceLCDWriteImage:data forEncoder:encoder];
}

- (void)deviceLCDWriteImage:(NSData *)data forEncoder:(int)encoder {
    
    int encoderWidth = self.lcdStripWidth / self.encoderColumns;
    
    int left        = (encoderWidth * encoder) - encoderWidth;
    int top         = 0;
    int width       = encoderWidth;
    int height      = self.lcdStripHeight;
    
    uint8_t reportHeader[] = {0x02,                             // 0: Report ID
                             0x0c,                              // 1: Image Rectangle JPEG
        
                            left & 0xFF,                        // 2: Left - the least significant byte
                            left >> 8,                          // 3: Left - the most significant byte
        
                            top & 0xFF,                         // 4: Top - the least significant byte
                            top >> 8,                           // 5: Top - the most significant byte
        
                            width & 0xFF,                       // 6: Width - the least significant byte
                            width >> 8,                         // 7: Width - the most significant byte
        
                            height & 0xFF,                      // 8: Height - the least significant byte
                            height >> 8,                        // 9: Height - the most significant byte
                                                         
                            0x00,                               // 10: Is Last Page (1 or 0)?
        
                            0x00,                               // 11: Page Number - the least significant byte
                            0x00,                               // 12: Page Number - the most significant byte
        
                            0x00,                               // 13: Payload Length - the least significant byte
                            0x00,                               // 14: Payload Length - the most significant byte
        
                            0x00                                // 15: Padding
                            };

    // The v2 Stream Decks needs images sent in slices no more than 1024 bytes minus the report header (16 bytes)
    int maxPayloadLength = self.lcdReportLength - self.lcdReportHeaderLength;

    int bytesRemaining = (int)data.length;
    int bytesSent = 0;
    int pageNumber = 0;
    const uint8_t *imageBuf = data.bytes;

    IOReturn result;

    while (bytesRemaining > 0) {
        int thisPageLength = MIN(bytesRemaining, maxPayloadLength);
        bytesSent = pageNumber * maxPayloadLength;

        // Set our current page number
        reportHeader[11] = pageNumber & 0xFF;
        reportHeader[12] = pageNumber >> 8;

        // Set our current page length
        reportHeader[13] = thisPageLength & 0xFF;
        reportHeader[14] = thisPageLength >> 8;

        // Set if we're the last page of data
        if (bytesRemaining <= maxPayloadLength) reportHeader[10] = 1;

        NSMutableData *report = [NSMutableData dataWithLength:self.lcdReportLength];
        [report replaceBytesInRange:NSMakeRange(0, self.lcdReportHeaderLength)
                          withBytes:reportHeader];
        [report replaceBytesInRange:NSMakeRange(self.lcdReportHeaderLength, thisPageLength)
                          withBytes:imageBuf+bytesSent
                             length:thisPageLength];

        result = IOHIDDeviceSetReport(self.device,
                                      kIOHIDReportTypeOutput,
                                      reportHeader[0],
                                      report.bytes,
                                      (int)report.length);
        if (result != kIOReturnSuccess) {
            NSLog(@"WARNING: writing an image with hs.streamdeck encountered a failure on page %d: %d", pageNumber, result);
        }

        bytesRemaining = bytesRemaining - thisPageLength;
        pageNumber++;
    }
}
@end
