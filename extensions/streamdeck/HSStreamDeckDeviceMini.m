//
//  HSStreamDeckDeviceMini.m
//  streamdeck
//
//  Created by Chris Jones on 25/11/2019.
//  Copyright © 2019 Hammerspoon. All rights reserved.
//
// Stream Deck Mini support was made possible by examining https://github.com/abcminiuser/python-elgato-streamdeck/tree/master/src/StreamDeck/Devices

#import "HSStreamDeckDeviceMini.h"

@implementation HSStreamDeckDeviceMini

- (id)initWithDevice:(IOHIDDeviceRef)device manager:(id)manager {
    self = [super initWithDevice:device manager:manager];
    if (self) {
        self.deckType = @"Elgato Stream Deck (Mini)";
        self.keyRows = 2;
        self.keyColumns = 3;
        self.imageWidth = 80;
        self.imageHeight = 80;
        self.imageWidthFullScreen = 320;
        self.imageHeightFullScreen = 240;
        self.imageCodec = STREAMDECK_CODEC_BMP;
        self.imageFlipX = NO;
        self.imageFlipY = YES;
        self.imageAngle = 90;
        self.simpleReportLength = 17;
        self.reportLength = 1024;
        self.reportHeaderLength = 16;
        self.dataKeyOffset = 1;

        uint8_t resetHeader[] = {0x0B, 0x63};
        self.resetCommand = [NSData dataWithBytes:resetHeader length:2];

        uint8_t brightnessHeader[] = {0x05, 0x55, 0xAA, 0xD1, 0x01, 0xFF};
        self.setBrightnessCommand = [NSData dataWithBytes:brightnessHeader length:6];

        self.serialNumberCommand = 0x03;
        self.firmwareVersionCommand = 0x4;

        self.serialNumberReadOffset = 5;
        self.firmwareReadOffset = 5;
    }
    return self;
}

- (void)deviceWriteImage:(NSData *)data button:(int)button {
    uint8_t reportMagic[] = {0x02,  // Report ID
                             0x01,  // Unknown (always seems to be 1)
                             0x00,  // Page Number
                             0x00,  // Padding
                             0x00,  // Last page Bool
                             button, // Deck button to set
                             0,
                             0,
                             0,
                             0,
                             0,
                             0,
                             0,
                             0,
                             0,
                             0,
                            };

    // The Mini Stream Deck needs images sent in slices no more than 1008 bytes
    int payloadLength = self.reportLength - self.reportHeaderLength;
    int imageLen = (int)data.length;
    int bytesRemaining = imageLen;
    int pageNumber = reportMagic[2];
    const uint8_t *imageBuf = data.bytes;
    IOReturn result;

    while (bytesRemaining > 0) {
        int reportLength = MIN(bytesRemaining, payloadLength);
        int bytesSent = pageNumber * payloadLength;

        // Set our current page number
        reportMagic[2] = pageNumber;
        // Set if we're the last page of data
        if (bytesRemaining <= payloadLength) reportMagic[4] = 1;

        NSMutableData *report = [NSMutableData dataWithLength:self.reportLength];
        [report replaceBytesInRange:NSMakeRange(0, self.reportHeaderLength) withBytes:reportMagic];
        [report replaceBytesInRange:NSMakeRange(self.reportHeaderLength, reportLength) withBytes:imageBuf+bytesSent length:reportLength];

        result = IOHIDDeviceSetReport(self.device, kIOHIDReportTypeOutput, reportMagic[0], report.bytes, (int)report.length);
        if (result != kIOReturnSuccess) {
            NSLog(@"WARNING: writing an image with hs.streamdeck encountered a failure on page %d: %d", pageNumber, result);
        }
        bytesRemaining = bytesRemaining - (int)report.length;
        pageNumber++;
    }
}
@end
