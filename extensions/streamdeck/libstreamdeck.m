@import Cocoa;
@import LuaSkin;

#import "HSStreamDeckManager.h"
#import "HSStreamDeckDevice.h"
#import "streamdeck.h"

#define get_objectFromUserdata(objType, L, idx, tag) (objType*)*((void**)luaL_checkudata(L, idx, tag))

static HSStreamDeckManager *deckManager;
LSRefTable streamDeckRefTable = LUA_NOREF;

#pragma mark - Lua API
static int streamdeck_gc(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    LSGCCanary tmpLSUUID = deckManager.lsCanary;
    [skin destroyGCCanary:&tmpLSUUID];
    deckManager.lsCanary = tmpLSUUID;

    [deckManager stopHIDManager];
    [deckManager doGC];
    return 0;
}

/// hs.streamdeck.init(fn)
/// Function
/// Initialises the Stream Deck driver and sets a discovery callback
///
/// Parameters:
///  * fn - A function that will be called when a Stream Deck is connected or disconnected. It should take the following arguments:
///   * A boolean, true if a device was connected, false if a device was disconnected
///   * An hs.streamdeck object, being the device that was connected/disconnected
///
/// Returns:
///  * None
///
/// Notes:
///  * This function must be called before any other parts of this module are used
static int streamdeck_init(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TFUNCTION, LS_TBREAK];

    deckManager = [[HSStreamDeckManager alloc] init];
    deckManager.discoveryCallbackRef = [skin luaRef:streamDeckRefTable atIndex:1];
    deckManager.lsCanary = [skin createGCCanary];
    [deckManager startHIDManager];

    return 0;
}

/// hs.streamdeck.discoveryCallback(fn)
/// Function
/// Sets/clears a callback for reacting to device discovery events
///
/// Parameters:
///  * fn - A function that will be called when a Stream Deck is connected or disconnected. It should take the following arguments:
///   * A boolean, true if a device was connected, false if a device was disconnected
///   * An hs.streamdeck object, being the device that was connected/disconnected
///
/// Returns:
///  * None
static int streamdeck_discoveryCallback(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TFUNCTION, LS_TBREAK];

    deckManager.discoveryCallbackRef = [skin luaUnref:streamDeckRefTable ref:deckManager.discoveryCallbackRef];

    if (lua_type(skin.L, 1) == LUA_TFUNCTION) {
        deckManager.discoveryCallbackRef = [skin luaRef:streamDeckRefTable atIndex:1];
    }

    return 0;
}

/// hs.streamdeck.numDevices()
/// Function
/// Gets the number of Stream Deck devices connected
///
/// Parameters:
///  * None
///
/// Returns:
///  * A number containing the number of Stream Deck devices attached to the system
static int streamdeck_numDevices(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TBREAK];

    lua_pushinteger(skin.L, deckManager.devices.count);
    return 1;
}

/// hs.streamdeck.getDevice(num)
/// Function
/// Gets an hs.streamdeck object for the specified device
///
/// Parameters:
///  * num - A number that should be within the bounds of the number of connected devices
///
/// Returns:
///  * An hs.streamdeck object
static int streamdeck_getDevice(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TNUMBER, LS_TBREAK];

    [skin pushNSObject:deckManager.devices[lua_tointeger(skin.L, 1) - 1]];
    return 1;
}

/// hs.streamdeck:buttonCallback(fn)
/// Method
/// Sets/clears the button callback function for a Stream Deck device
///
/// Parameters:
///  * fn - A function to be called when a button is pressed/released on the stream deck. It should receive three arguments:
///   * The hs.streamdeck userdata object
///   * A number containing the button that was pressed/released
///   * A boolean indicating whether the button was pressed (true) or released (false)
///
/// Returns:
///  * The hs.streamdeck device
static int streamdeck_buttonCallback(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TFUNCTION | LS_TNIL, LS_TBREAK];

    HSStreamDeckDevice *device = [skin luaObjectAtIndex:1 toClass:"HSStreamDeckDevice"];
    device.buttonCallbackRef = [skin luaUnref:streamDeckRefTable ref:device.buttonCallbackRef];

    if (lua_type(skin.L, 2) == LUA_TFUNCTION) {
        device.buttonCallbackRef = [skin luaRef:streamDeckRefTable atIndex:2];
    }

    lua_pushvalue(skin.L, 1);
    return 1;
}

/// hs.streamdeck:encoderCallback(fn)
/// Method
/// Sets/clears the knob/encoder callback function for a Stream Deck Plus.
///
/// Parameters:
///  * fn - A function to be called when an encoder button is pressed/released/rotated on a Stream Deck Plus. It should receive five arguments:
///   * The hs.streamdeck userdata object
///   * A number containing the button that was pressed/released/rotated
///   * A boolean indicating whether the button was pressed (true) or released (false)
///   * A boolean indicating that the button was turned left
///   * A boolean indicating that the button was turned right
///
/// Returns:
///  * The hs.streamdeck device
static int streamdeck_encoderCallback(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TFUNCTION | LS_TNIL, LS_TBREAK];

    HSStreamDeckDevice *device = [skin luaObjectAtIndex:1 toClass:"HSStreamDeckDevice"];
    device.encoderCallbackRef = [skin luaUnref:streamDeckRefTable ref:device.encoderCallbackRef];

    if (lua_type(skin.L, 2) == LUA_TFUNCTION) {
        device.encoderCallbackRef = [skin luaRef:streamDeckRefTable atIndex:2];
    }

    lua_pushvalue(skin.L, 1);
    return 1;
}

/// hs.streamdeck:screenCallback(fn)
/// Method
/// Sets/clears the screen callback function for a Stream Deck Plus's touch screen (above the encoder knobs).
///
/// Parameters:
///  * fn - A function to be called when a screen is pressed/released/swiped on a Stream Deck Plus. It should receive six arguments:
///   * The hs.streamdeck userdata object
///   * A string either containing "shortPress", "longPress" or "swipe"
///   * The X position of where the screen was first touched
///   * The Y position of where the screen was first touched
///   * The X position of where the screen was last touched (if swiping)
///   * The Y position of where the screen was last touched (if swiping)
///
/// Returns:
///  * The hs.streamdeck device
static int streamdeck_screenCallback(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TFUNCTION | LS_TNIL, LS_TBREAK];

    HSStreamDeckDevice *device = [skin luaObjectAtIndex:1 toClass:"HSStreamDeckDevice"];
    device.screenCallbackRef = [skin luaUnref:streamDeckRefTable ref:device.screenCallbackRef];

    if (lua_type(skin.L, 2) == LUA_TFUNCTION) {
        device.screenCallbackRef = [skin luaRef:streamDeckRefTable atIndex:2];
    }

    lua_pushvalue(skin.L, 1);
    return 1;
}

/// hs.streamdeck:setBrightness(brightness)
/// Method
/// Sets the brightness of a Stream Deck device
///
/// Parameters:
///  * brightness - A whole number between 0 and 100 indicating the percentage brightness level to set
///
/// Returns:
///  * The hs.streamdeck device
static int streamdeck_setBrightness(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TNUMBER, LS_TBREAK];

    HSStreamDeckDevice *device = [skin luaObjectAtIndex:1 toClass:"HSStreamDeckDevice"];

    [device setBrightness:(int)lua_tointeger(skin.L, 2)];

    lua_pushvalue(skin.L, 1);
    return 1;
}

/// hs.streamdeck:reset()
/// Method
/// Resets a Stream Deck device
///
/// Parameters:
///  * None
///
/// Returns:
///  * The hs.streamdeck object
static int streamdeck_reset(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK];

    HSStreamDeckDevice *device = [skin luaObjectAtIndex:1 toClass:"HSStreamDeckDevice"];
    [device reset];

    lua_pushvalue(skin.L, 1);
    return 1;
}

/// hs.streamdeck:serialNumber()
/// Method
/// Gets the serial number of a Stream Deck device
///
/// Parameters:
///  * None
///
/// Returns:
///  * A string containing the serial number of the deck
static int streamdeck_serialNumber(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK];

    HSStreamDeckDevice *device = [skin luaObjectAtIndex:1 toClass:"HSStreamDeckDevice"];

    [skin pushNSObject:device.serialNumber];
    return 1;
}

/// hs.streamdeck:firmwareVersion()
/// Method
/// Gets the firmware version of a Stream Deck device
///
/// Parameters:
///  * None
///
/// Returns:
///  * A string containing the firmware version of the deck
static int streamdeck_firmwareVersion(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK];

    HSStreamDeckDevice *device = [skin luaObjectAtIndex:1 toClass:"HSStreamDeckDevice"];

    [skin pushNSObject:[device firmwareVersion]];
    return 1;
}

/// hs.streamdeck:buttonLayout()
/// Method
/// Gets the layout of buttons a Stream Deck device has
///
/// Parameters:
///  * None
///
/// Returns:
///  * The number of columns
///  * The number of rows
static int streamdeck_buttonLayout(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK];

    HSStreamDeckDevice *device = [skin luaObjectAtIndex:1 toClass:"HSStreamDeckDevice"];

    lua_pushinteger(skin.L, device.keyColumns);
    lua_pushinteger(skin.L, device.keyRows);
    return 2;
}

/// hs.streamdeck:imageSize()
/// Method
/// Gets the width and height of the buttons in pixels
///
/// Parameters:
///  * None
///
/// Returns:
///  * An table with keys `w` and `h` containing the width and height, respectively, of images expected by the Stream Deck
static int streamdeck_imageSize(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK];

    HSStreamDeckDevice *device = [skin luaObjectAtIndex:1 toClass:"HSStreamDeckDevice"];

    NSSize size = NSMakeSize(device.imageWidth, device.imageHeight);
    [skin pushNSSize:size];
    return 1;
}

/// hs.streamdeck:imageSizeFullScreen()
/// Method
/// Gets the width and height of the whole physical screen lying under buttons (treating all the buttons as a single big screen).
///
/// Parameters:
///  * None
///
/// Returns:
///  * An table with keys `w` and `h` containing the width and height, respectively, of images expected by the Stream Deck
static int streamdeck_imageSizeFullScreen(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TBREAK];

    HSStreamDeckDevice *device = [skin luaObjectAtIndex:1 toClass:"HSStreamDeckDevice"];

    NSSize size = NSMakeSize(device.imageWidthFullScreen, device.imageHeightFullScreen);
    [skin pushNSSize:size];
    return 1;
}

/// hs.streamdeck:setButtonImage(button, image)
/// Method
/// Sets the image of a button on the Stream Deck device
///
/// Parameters:
///  * button - A number (from 1 to 15) describing which button to set the image for
///  * image - An hs.image object
///
/// Returns:
///  * The hs.streamdeck object
static int streamdeck_setButtonImage(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TNUMBER, LS_TUSERDATA, "hs.image", LS_TBREAK];

    HSStreamDeckDevice *device = [skin luaObjectAtIndex:1 toClass:"HSStreamDeckDevice"];

    [device setImage:[skin luaObjectAtIndex:3 toClass:"NSImage"] forButton:(int)lua_tointeger(skin.L, 2)];

    lua_pushvalue(skin.L, 1);
    return 1;
}

/// hs.streamdeck:setFullScreenImage(image)
/// Method
/// Sets the image of a physical screen lying under buttons on the Stream Deck device (treating all the buttons as a single big screen).
///
/// Parameters:
///  * image - An hs.image object
///
/// Returns:
///  * The hs.streamdeck object
///
/// Notes:
///  * Images are always stretched to fill the entire screen without preserving the aspect ratio. To apply different scaling consider using [hs.canvas](hs.canvas.html) and/or [hs.image:size()](hs.image.html#size).
static int streamdeck_setFullScreenImage(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TUSERDATA, "hs.image", LS_TBREAK];

    HSStreamDeckDevice *device = [skin luaObjectAtIndex:1 toClass:"HSStreamDeckDevice"];

    [device setImageFullScreen:[skin luaObjectAtIndex:2 toClass:"NSImage"]];

    lua_pushvalue(skin.L, 1);
    return 1;
}

/// hs.streamdeck:setScreenImage(encoder, image)
/// Method
/// Sets the image of the screen on the Stream Deck device
///
/// Parameters:
///  * encoder - A number (from 1 to 4) describing which encoder to set the image for
///  * image - An hs.image object
///
/// Returns:
///  * The hs.streamdeck object
static int streamdeck_setScreenImage(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TNUMBER, LS_TUSERDATA, "hs.image", LS_TBREAK];

    HSStreamDeckDevice *device = [skin luaObjectAtIndex:1 toClass:"HSStreamDeckDevice"];
    
    [device setLCDImage:[skin luaObjectAtIndex:3 toClass:"NSImage"] forEncoder:(int)lua_tointeger(skin.L, 2)];
    
    lua_pushvalue(skin.L, 1);
    return 1;
}

/// hs.streamdeck:setButtonColor(button, color)
/// Method
/// Sets a button on the Stream Deck device to the specified color
///
/// Parameters:
///  * button - A number (from 1 to 15) describing which button to set the color on
///  * color - An hs.drawing.color object
///
/// Returns:
///  * The hs.streamdeck object
static int streamdeck_setButtonColor(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TNUMBER, LS_TTABLE, LS_TBREAK];

    HSStreamDeckDevice *device = [skin luaObjectAtIndex:1 toClass:"HSStreamDeckDevice"];

    [device setColor:[skin luaObjectAtIndex:3 toClass:"NSColor"] forButton:(int)lua_tointeger(skin.L, 2)];

    lua_pushvalue(skin.L, 1);
    return 1;
}

/// hs.streamdeck:setFullScreenColor(color)
/// Method
/// Sets the whole physical screen on the Stream Deck device to the specified color (treating all the buttons as a single big screen).
///
/// Parameters:
///  * color - An hs.drawing.color object
///
/// Returns:
///  * The hs.streamdeck object
static int streamdeck_setFullScreenColor(lua_State *L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    [skin checkArgs:LS_TUSERDATA, USERDATA_TAG, LS_TTABLE, LS_TBREAK];

    HSStreamDeckDevice *device = [skin luaObjectAtIndex:1 toClass:"HSStreamDeckDevice"];

    [device setColorFullScreen:[skin luaObjectAtIndex:2 toClass:"NSColor"]];

    lua_pushvalue(skin.L, 1);
    return 1;
}

#pragma mark - Lua<->NSObject Conversion Functions
// These must not throw a lua error to ensure LuaSkin can safely be used from Objective-C
// delegates and blocks.

static int pushHSStreamDeckDevice(lua_State *L, id obj) {
    HSStreamDeckDevice *value = obj;
    value.selfRefCount++;
    void** valuePtr = lua_newuserdata(L, sizeof(HSStreamDeckDevice *));
    *valuePtr = (__bridge_retained void *)value;
    luaL_getmetatable(L, USERDATA_TAG);
    lua_setmetatable(L, -2);
    return 1;
}

static id toHSStreamDeckDeviceFromLua(lua_State *L, int idx) {
    LuaSkin *skin = [LuaSkin sharedWithState:L] ;
    HSStreamDeckDevice *value ;
    if (luaL_testudata(L, idx, USERDATA_TAG)) {
        value = get_objectFromUserdata(__bridge HSStreamDeckDevice, L, idx, USERDATA_TAG) ;
    } else {
        [skin logError:[NSString stringWithFormat:@"expected %s object, found %s", USERDATA_TAG,
                        lua_typename(L, lua_type(L, idx))]] ;
    }
    return value ;
}

#pragma mark - Hammerspoon/Lua Infrastructure

static int streamdeck_object_tostring(lua_State* L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L] ;
    HSStreamDeckDevice *obj = [skin luaObjectAtIndex:1 toClass:"HSStreamDeckDevice"] ;
    NSString *title = [NSString stringWithFormat:@"%@, serial: %@", obj.deckType, obj.serialNumber];
    [skin pushNSObject:[NSString stringWithFormat:@"%s: %@ (%p)", USERDATA_TAG, title, lua_topointer(L, 1)]] ;
    return 1 ;
}

static int streamdeck_object_eq(lua_State* L) {
    // can't get here if at least one of us isn't a userdata type, and we only care if both types are ours,
    // so use luaL_testudata before the macro causes a lua error
    if (luaL_testudata(L, 1, USERDATA_TAG) && luaL_testudata(L, 2, USERDATA_TAG)) {
        LuaSkin *skin = [LuaSkin sharedWithState:L] ;
        HSStreamDeckDevice *obj1 = [skin luaObjectAtIndex:1 toClass:"HSStreamDeckDevice"] ;
        HSStreamDeckDevice *obj2 = [skin luaObjectAtIndex:2 toClass:"HSStreamDeckDevice"] ;
        lua_pushboolean(L, [obj1 isEqualTo:obj2]) ;
    } else {
        lua_pushboolean(L, NO) ;
    }
    return 1 ;
}

static int streamdeck_object_gc(lua_State* L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L] ;
    HSStreamDeckDevice *theDevice = get_objectFromUserdata(__bridge_transfer HSStreamDeckDevice, L, 1, USERDATA_TAG) ;
    if (theDevice) {
        theDevice.selfRefCount-- ;
        if (theDevice.selfRefCount == 0) {
            theDevice.buttonCallbackRef = [skin luaUnref:streamDeckRefTable ref:theDevice.buttonCallbackRef] ;
            theDevice.encoderCallbackRef = [skin luaUnref:streamDeckRefTable ref:theDevice.encoderCallbackRef] ;
            theDevice.screenCallbackRef = [skin luaUnref:streamDeckRefTable ref:theDevice.screenCallbackRef] ;
            theDevice = nil ;
        }
    }

    // Remove the Metatable so future use of the variable in Lua won't think its valid
    lua_pushnil(L) ;
    lua_setmetatable(L, 1) ;
    return 0 ;
}

#pragma mark - Lua object function definitions
static const luaL_Reg userdata_metaLib[] = {
    {"serialNumber",        streamdeck_serialNumber},
    {"firmwareVersion",     streamdeck_firmwareVersion},
    {"buttonLayout",        streamdeck_buttonLayout},
    {"imageSize",           streamdeck_imageSize},
    {"imageSizeFullScreen", streamdeck_imageSizeFullScreen},
    
    {"buttonCallback",      streamdeck_buttonCallback},
    {"encoderCallback",     streamdeck_encoderCallback},
    {"screenCallback",      streamdeck_screenCallback},
    
    {"setButtonImage",      streamdeck_setButtonImage},
    {"setFullScreenImage",  streamdeck_setFullScreenImage},
    {"setScreenImage",      streamdeck_setScreenImage},
    {"setButtonColor",      streamdeck_setButtonColor},
    {"setFullScreenColor",  streamdeck_setFullScreenColor},
    {"setBrightness",       streamdeck_setBrightness},
    {"reset",               streamdeck_reset},

    {"__tostring",          streamdeck_object_tostring},
    {"__eq",                streamdeck_object_eq},
    {"__gc",                streamdeck_object_gc},
    
    {NULL, NULL}
};

#pragma mark - Lua Library function definitions
static const luaL_Reg streamdecklib[] = {
    {"init",                streamdeck_init},
    {"discoveryCallback",   streamdeck_discoveryCallback},
    {"numDevices",          streamdeck_numDevices},
    {"getDevice",           streamdeck_getDevice},

    {NULL, NULL}
};

static const luaL_Reg metalib[] = {
    {"__gc", streamdeck_gc},

    {NULL, NULL}
};

#pragma mark - Lua initialiser
int luaopen_hs_libstreamdeck(lua_State* L) {
    LuaSkin *skin = [LuaSkin sharedWithState:L];
    streamDeckRefTable = [skin registerLibrary:USERDATA_TAG functions:streamdecklib metaFunctions:metalib];
    [skin registerObject:USERDATA_TAG objectFunctions:userdata_metaLib];

    [skin registerPushNSHelper:pushHSStreamDeckDevice         forClass:"HSStreamDeckDevice"];
    [skin registerLuaObjectHelper:toHSStreamDeckDeviceFromLua forClass:"HSStreamDeckDevice" withTableMapping:USERDATA_TAG];

    return 1;
}

