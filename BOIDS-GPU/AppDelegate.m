//
//  AppDelegate.m
//  BOIDS_Analysis1
//
//  Created by Tatsuo Unemi on 2024/11/14.
//

#import "AppDelegate.h"
#import "AgentCPU.h"
#import "AgentGPU.h"
#import "MetalView.h"
@import UniformTypeIdentifiers;

void in_main_thread(void (^block)(void)) {
	if ([NSThread isMainThread]) block();
	else dispatch_async(dispatch_get_main_queue(), block);
}
static void show_alert(NSObject *object, short err, BOOL fatal) {
	in_main_thread( ^{
		NSAlert *alt;
		if ([object isKindOfClass:NSError.class])
			alt = [NSAlert alertWithError:(NSError *)object];
		else {
			NSString *str = [object isKindOfClass:NSString.class]?
				(NSString *)object : object.description;
			if (err != noErr)
				str = [NSString stringWithFormat:@"%@\nerror code = %d", str, err];
			alt = NSAlert.new;
			alt.alertStyle = fatal? NSAlertStyleCritical : NSAlertStyleWarning;
			alt.messageText = [NSString stringWithFormat:@"%@ in %@",
				fatal? @"Error" : @"Warning",
				[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"]];
			alt.informativeText = str;
		}
		[alt runModal];
		if (fatal) [NSApp terminate:nil];
	} );
}
void err_msg(NSObject *object, BOOL fatal) {
	show_alert(object, 0, fatal);
}
void unix_error_msg(NSString *msg, BOOL fatal) {
	show_alert([NSString stringWithFormat:@"%@: %s.", msg, strerror(errno)], errno, fatal);
}
static void error_msg(NSString *msg, short err) {
	show_alert(msg, err, NO);
}

static NSString *keyFullScreenStart = @"FullScreenStart", *keyRunningStart = @"RunningStart";
@interface AppDelegate ()
@property (strong) IBOutlet NSWindow *window;
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
	check_initial_communication();
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	BOOL fullScrStart = [ud boolForKey:keyFullScreenStart],
		runningStart = [ud boolForKey:keyRunningStart];
	MetalView *mtlView = _metalView;
	[NSTimer scheduledTimerWithTimeInterval:.5 repeats:NO block:^(NSTimer *timer) {
		[self openPanel:nil];
		[self openCommPanel:nil];
		if (fullScrStart) [mtlView fullScreen:nil];
		if (runningStart) [mtlView playPause:nil];
	}];
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
	return _pnlCntl? [_pnlCntl appTerminate] : NSTerminateNow;
}
- (void)applicationWillTerminate:(NSNotification *)notification {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	if (_metalView.view.isInFullScreenMode)
		[ud setBool:YES forKey:keyFullScreenStart];
	else [ud removeObjectForKey:keyFullScreenStart];
	if (_metalView.isRunning)
		[ud setBool:YES forKey:keyRunningStart];
	else [ud removeObjectForKey:keyRunningStart];
}
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
	return YES;
}
- (IBAction)openPanel:(id)sender {
	if (_pnlCntl == nil) _pnlCntl = [PanelController.alloc initWithWindow:nil];
	[_pnlCntl showWindow:nil];
}
- (IBAction)openCommPanel:(id)sender {
	if (_pnlComm == nil) _pnlComm = [CommPanel.alloc initWithWindow:nil];
	[_pnlComm showWindow:nil];
}
- (IBAction)openStatistics:(id)sender {
	if (statistics == nil) statistics = [Statistics.alloc initWithWindow:nil];
	[statistics showWindow:nil];
}
@end

static NSString *keyPopSize = @"PopSize", *acNmPopSize = @"Population Size";
static NSInteger PopSizeDefault;
enum { ColorBg, ColorAgnt, ColorFog, NColors };
static MyRGB ColorDefault[NColors] = {{0,0,0}, {1,1,1}, {.5,.5,.5}};
static MyRGB Colors[NColors];
static NSString *ColorNames[NColors] = {@"Background", @"AgentColor", @"FogColor"};
static NSString *keyShapeType = @"ShapeType", *keyColorful = @"Colorful",
	*keyFullScreenName = @"FullScreenName";
NSString *FullScreenName = nil;

@implementation PanelController {
	IBOutlet NSTextField *popSizeDgt;
	IBOutlet NSButton *ppSzApplyBtn;
	IBOutlet NSSlider *avdSld, *cohSld, *aliSld, *attrSld,
		*sightDSld, *sightASld, *masSld, *mxsSld, *mnsSld, *frcSld;
	IBOutlet NSTextField *avdDgt, *cohDgt, *aliDgt, *attrDgt,
		*sightDDgt, *sightADgt, *masDgt, *mxsDgt, *mnsDgt, *frcDgt;
	IBOutlet NSTextField *depthDgt, *scaleDgt, *cntrstDgt,
		*agntSizeDgt, *agntOpacityDgt, *shadowDgt, *fogDgt;
	IBOutlet NSSlider *depthSld, *scaleSld, *cntrstSld,
		*agntSizeSld, *agntOpacitySld, *shadowSld, *fogSld;
	IBOutlet NSColorWell *bgColWel, *bdColWel, *fogColWel;
	IBOutlet NSPopUpButton *shapePopUp, *fullScrPopUp;
	IBOutlet NSButton *colorfulCBox, *revertBtn, *saveBtn, *resetBtn, *saveAsBtn;
	NSArray<NSTextField *> *digits;
	NSArray<NSSlider *> *sliders;
	NSArray<NSColorWell *> *colWels;
	NSUndoManager *undoMngr;
}
- (NSString *)windowNibName { return @"Panel"; }
- (instancetype)initWithWindow:(NSWindow *)win {
	if ((self = [super initWithWindow:win]) == nil) return nil;
	undoMngr = NSUndoManager.new;
	return self;
}
static NSInteger default_popSize(void) {
	NSNumber *num = [NSUserDefaults.standardUserDefaults objectForKey:keyPopSize];
	return num? num.integerValue : PopSizeDefault;
}
static NSString *label_from_tag(NSInteger tag) {
	return (tag < N_PARAMS)? PrmLabels[tag] : ViewPrmLbls[tag - N_PARAMS];
}
static inline CGFloat factory_default(NSInteger idx) {
	return (idx < N_PARAMS)? 0. : ((float *)(&DfltViewPrms))[idx - N_PARAMS];
}
static CGFloat default_value(NSInteger idx) {
	NSNumber *num = [NSUserDefaults.standardUserDefaults objectForKey:label_from_tag(idx)];
	return num? num.doubleValue : factory_default(idx);
}
static CGFloat get_param_value(NSInteger idx) {
	return (idx < N_PARAMS)?
		((float *)(&PrmsUI))[idx] : ((float *)(&ViewPrms))[idx - N_PARAMS];
}
static void set_param_value(NSInteger idx, CGFloat value) {
	if (idx < N_PARAMS) {
		((float *)(&PrmsUI))[idx] = value;
		set_sim_params();
	} else ((float *)(&ViewPrms))[idx - N_PARAMS] = value;
}
static ShapeType default_shapeType(void) {
	NSNumber *num = [NSUserDefaults.standardUserDefaults objectForKey:keyShapeType];
	return (num == nil)? ShapePaperPlane : (ShapeType)num.intValue;
}
static BOOL default_colorful(void) {
	NSNumber *num = [NSUserDefaults.standardUserDefaults objectForKey:keyColorful];
	return (num == nil)? YES : num.boolValue;
}
static MyRGB myRGB_from_array(NSArray<NSNumber *> *arr) {
	return (MyRGB){arr[0].doubleValue, arr[1].doubleValue, arr[2].doubleValue};
}
static NSArray<NSNumber *> *myRGB_to_array(MyRGB rgb) {
	return @[@(rgb.red), @(rgb.green), @(rgb.blue)];
}
static MyRGB default_color(NSInteger idx) {
	NSArray<NSNumber *> *arr =
		[NSUserDefaults.standardUserDefaults objectForKey:ColorNames[idx]];
	return (arr == nil)? ColorDefault[idx] : myRGB_from_array(arr);
}
static NSColor *myRGB_to_color(MyRGB rgb) {
	return [NSColor colorWithRed:rgb.red green:rgb.green blue:rgb.blue alpha:1.];
}
static NSString *default_screen(void) {
	return [NSUserDefaults.standardUserDefaults objectForKey:keyFullScreenName];
}
static BOOL equal_screen_names(NSObject *a, NSObject *b) {
	if (a == nil) a = @NO;
	if (b == nil) b = @NO;
	return [a isEqualTo:b];
}
- (void)checkButtonEnabled {
	BOOL reset = NewPopSize != PopSizeDefault, save = NewPopSize != default_popSize();
	for (NSInteger i = 0; i < sliders.count && !(reset && save); i ++) {
		CGFloat val = sliders[i].doubleValue;
		CGFloat dfl = default_value(i);
		if (val != factory_default(i)) reset = YES;
		if (fabs(val - dfl) > 1e-6) save = YES;
	}
	for (NSInteger i = 0; i < NColors && !(reset && save); i ++) {
		MyRGB dfl = default_color(i);
		if (memcmp(&Colors[i], &dfl, sizeof(MyRGB)) != 0) save = YES;
		if (memcmp(&Colors[i], &ColorDefault[i], sizeof(MyRGB)) != 0) reset = YES;
	}
	if (!reset) reset = shapeType != ShapePaperPlane;
	if (!save) save = shapeType != default_shapeType();
	if (!reset) reset = !Colorful;
	if (!save) save = Colorful != default_colorful();
	if (!save) save = !equal_screen_names(FullScreenName, default_screen());
	resetBtn.enabled = saveAsBtn.enabled = reset;
	revertBtn.enabled = saveBtn.enabled = save;
}
static void load_color_default(int colID, simd_float3 *rgbv) {
	NSArray<NSNumber *> *arr;
	if ((arr = [NSUserDefaults.standardUserDefaults
		objectForKey:ColorNames[colID]]) != nil) {
		MyRGB rgb = Colors[colID] = myRGB_from_array(arr);
		*rgbv = (simd_float3){rgb.red, rgb.green, rgb.blue};
	}
}
void load_defaults(void) {
	NSNumber *num;
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	PopSizeDefault = NewPopSize = PopSize;
	if ((num = [ud objectForKey:keyPopSize]) != nil)
		NewPopSize = PopSize = num.integerValue;
	for (NSInteger i = 0; i < N_PARAMS + N_VPARAMS; i ++)
		if ((num = [ud objectForKey:label_from_tag(i)]) != nil)
			set_param_value(i, num.doubleValue);
	memcpy(Colors, ColorDefault, sizeof(Colors));
	load_color_default(ColorBg, &WallRGB);
	load_color_default(ColorAgnt, &AgntRGB);
	load_color_default(ColorFog, &FogRGB);
	if ((num = [ud objectForKey:keyShapeType]) != nil) shapeType = num.intValue;
	if ((num = [ud objectForKey:keyColorful]) != nil) Colorful = num.boolValue;
	FullScreenName = default_screen();
}
- (void)adjustFullScrItemSelection:(NSString *)title {
	if (title == nil) title = fullScrPopUp.lastItem.title;
	NSMenuItem *item = [fullScrPopUp itemWithTitle:title];
	[fullScrPopUp selectItem:(item != nil)? item : fullScrPopUp.lastItem];
}
- (void)configureScreenMenu {
	[fullScrPopUp removeAllItems];
	for (NSScreen *scr in NSScreen.screens)
		[fullScrPopUp addItemWithTitle:scr.localizedName];
	[fullScrPopUp addItemWithTitle:@"Last Screen"];
	[self adjustFullScrItemSelection:FullScreenName];
	fullScrPopUp.enabled = (NSScreen.screens.count > 1);
}
static void displayReconfigCB(CGDirectDisplayID display,
	CGDisplayChangeSummaryFlags flags, void *userInfo) {
	if ((flags & kCGDisplayBeginConfigurationFlag) != 0 ||
		(flags & (kCGDisplayAddFlag | kCGDisplayRemoveFlag |
		kCGDisplayEnabledFlag | kCGDisplayDisabledFlag)) == 0) return;
	in_main_thread(^{ [(__bridge PanelController *)userInfo configureScreenMenu]; });
}
- (void)windowDidLoad {
	popSizeDgt.integerValue = PopSize;
	sliders = @[avdSld, cohSld, aliSld, attrSld, sightDSld, sightASld,
		masSld, mxsSld, mnsSld, frcSld, depthSld, scaleSld, cntrstSld,
		agntSizeSld, agntOpacitySld, shadowSld, fogSld];
	digits = @[avdDgt, cohDgt, aliDgt, attrDgt, sightDDgt, sightADgt,
		masDgt, mxsDgt, mnsDgt, frcDgt, depthDgt, scaleDgt, cntrstDgt,
		agntSizeDgt, agntOpacityDgt, shadowDgt, fogDgt];
	for (NSInteger i = 0; i < sliders.count; i ++) {
		sliders[i].doubleValue = digits[i].doubleValue = get_param_value(i);
		sliders[i].tag = digits[i].tag = i;
		sliders[i].target = digits[i].target = self;
		sliders[i].action = digits[i].action = @selector(changeValue:);
	}
	colWels = @[bgColWel, bdColWel, fogColWel];
	for (NSInteger i = 0; i < NColors; i ++)
		colWels[i].color = myRGB_to_color(Colors[i]);
	[shapePopUp selectItemAtIndex:shapeType];
	[self configureScreenMenu];
	CGError error = CGDisplayRegisterReconfigurationCallback(displayReconfigCB, (void *)self);
	if (error != kCGErrorSuccess)
		error_msg(@"Could not register a callback for display reconfiguration,", error);
	[self checkButtonEnabled];
	[NSNotificationCenter.defaultCenter
		addObserverForName:NSWindowDidChangeOcclusionStateNotification
		object:NSColorPanel.sharedColorPanel queue:nil usingBlock:
		^(NSNotification * _Nonnull notification) {
		NSColorPanel.sharedColorPanel.showsAlpha = NO;		
	}];
}
- (NSApplicationTerminateReply)appTerminate {
	if (!saveBtn.enabled) return NSTerminateNow;
	NSAlert *alert = NSAlert.new;
	alert.alertStyle = NSAlertStyleWarning;
	alert.messageText = @"Do you want to save the settings?";
	alert.informativeText = @"Parameter values have changed but not saved as defaults.";
	[alert addButtonWithTitle:@"Save"];
	[alert addButtonWithTitle:@"Don't save"];
	[alert addButtonWithTitle:@"Cancel"];
	switch ([alert runModal]) {
		case NSAlertFirstButtonReturn: [self saveAsDefault:saveBtn];
		case NSAlertSecondButtonReturn: return NSTerminateNow;
		default: return NSTerminateCancel;
	}
}
- (void)resetCamera {
	depthSld.doubleValue = scaleSld.doubleValue = 0.;
	[depthSld sendAction:depthSld.action to:depthSld.target];
	[scaleSld sendAction:scaleSld.action to:scaleSld.target];
}
- (void)camDepthModified {
	depthSld.doubleValue = depthDgt.doubleValue = ViewPrms.depth;
}
- (void)camScaleModified {
	scaleSld.doubleValue = scaleDgt.doubleValue = ViewPrms.scale;
}
static void set_popSize(NSInteger newSize) {
	[((AppDelegate *)NSApp.delegate).metalView revisePopSize:newSize];
}
- (IBAction)changePopSizeDgt:(id)sender {
	ppSzApplyBtn.enabled = NewPopSize != popSizeDgt.integerValue;
}
- (IBAction)applyNewPopSize:(id)sender {
	NSInteger newSize = popSizeDgt.integerValue;
	if (NewPopSize != newSize) {
		NSInteger orgSize = NewPopSize;
		set_popSize(newSize);
		[undoMngr registerUndoWithTarget:popSizeDgt handler:^(NSTextField *dgt) {
			dgt.integerValue = orgSize;
			[self applyNewPopSize:nil];
		}];
		if (!(undoMngr.undoing || undoMngr.redoing))
			undoMngr.actionName = acNmPopSize;
	}
	ppSzApplyBtn.enabled = NO;
	[self checkButtonEnabled];
}
- (IBAction)changeValue:(NSControl *)sender {
	NSInteger tag = sender.tag;
	CGFloat value = sender.doubleValue;
	NSControl *cntrPrt =
		[sender isKindOfClass:NSSlider.class]? digits[tag] : sliders[tag];
	CGFloat orgVal = cntrPrt.doubleValue;
	if (orgVal == value) return;
	cntrPrt.doubleValue = value;
	set_param_value(tag, value);
	if (tag == SIGHT_DIST_IDX)
		[((AppDelegate *)NSApp.delegate).metalView reviseSightDistance];
	[undoMngr registerUndoWithTarget:sender handler:^(NSControl *cntl) {
		cntl.doubleValue = orgVal;
		[cntl sendAction:cntl.action to:cntl.target]; 
	}];
	if (!undoMngr.isUndoing && !undoMngr.isRedoing)
		undoMngr.actionName = label_from_tag(tag);
	[self checkButtonEnabled];
	if (tag >= N_PARAMS) {
		MTKView *view = ((AppDelegate *)NSApp.delegate).metalView.view;
		if (view.paused) view.needsDisplay = YES;
	}
}
static void set_shape_type(ShapeType newType) {
	shapeType = newType;
	MTKView *view = ((AppDelegate *)NSApp.delegate).metalView.view;
	if (view.paused) view.needsDisplay = YES;
}
- (IBAction)chooseShape:(id)sender {
	ShapeType newType = (ShapeType)shapePopUp.indexOfSelectedItem;
	if (shapeType == newType) return;
	ShapeType orgType = shapeType;
	set_shape_type(newType);
	[undoMngr registerUndoWithTarget:shapePopUp handler:^(NSPopUpButton *popup) {
		[popup selectItemAtIndex:orgType];
		[popup sendAction:popup.action to:popup.target];
	}];
	[self checkButtonEnabled];
	if (!(undoMngr.undoing || undoMngr.redoing))
		undoMngr.actionName = @"Agent Shape";
}
- (IBAction)switchColorful:(id)sender {
	BOOL newValue = colorfulCBox.state == NSControlStateValueOn;
	if (Colorful == newValue) return;
	[undoMngr registerUndoWithTarget:colorfulCBox handler:^(NSButton *cbox) {
		cbox.state = !cbox.state;
		[cbox sendAction:cbox.action to:cbox.target];
	}];
	Colorful = newValue;
	((AppDelegate *)NSApp.delegate).metalView.view.needsDisplay = YES;
	[self checkButtonEnabled];
	if (!(undoMngr.undoing || undoMngr.redoing))
		undoMngr.actionName = @"Colorful";
}
static void set_color_value(NSInteger idx, MyRGB rgb) {
	MTKView *view = ((AppDelegate *)NSApp.delegate).metalView.view;
	simd_float3 RGB = (simd_float3){rgb.red, rgb.green, rgb.blue};
	switch (idx) {
		case ColorBg: WallRGB = RGB; break;
		case ColorAgnt: AgntRGB = RGB; break;
		case ColorFog: FogRGB = RGB;
	}
	if (view.paused) view.needsDisplay = YES;
}
- (void)changeColourOf:(NSInteger)idx rgb:(MyRGB)rgb {
	MyRGB orgRGB = Colors[idx];
	Colors[idx] = rgb;
	set_color_value(idx, rgb);
	[self checkButtonEnabled];
	[undoMngr registerUndoWithTarget:colWels[idx] handler:^(NSColorWell *target) {
		target.color = myRGB_to_color(orgRGB);
		[self changeColourOf:idx rgb:orgRGB];
	}];
}
- (IBAction)changeColour:(NSColorWell *)sender {
	CGFloat red, green, blue;
	[[sender.color colorUsingColorSpace:NSColorSpace.genericRGBColorSpace]
		getRed:&red green:&green blue:&blue alpha:NULL];
	MyRGB newCol = {red, green, blue};
	if (memcmp(&newCol, &Colors[sender.tag], sizeof(MyRGB)) == 0) return;
	[self changeColourOf:sender.tag rgb:newCol];
	undoMngr.actionName = ColorNames[sender.tag];
}
- (IBAction)chooseScreen:(id)sender {
	FullScreenName =
		(fullScrPopUp.indexOfSelectedItem == fullScrPopUp.numberOfItems - 1)?
		nil : fullScrPopUp.titleOfSelectedItem;
	[self checkButtonEnabled];
}
- (void)setValuesFromDict:(NSDictionary *)dict {
	NSNumber *num;
	NSArray<NSNumber *> *arr;
	NSMutableDictionary *md = NSMutableDictionary.new;
	if ((num = dict[keyPopSize]) != nil) {
		NSInteger newSize = num.integerValue;
		if (newSize != NewPopSize) {
			md[keyPopSize] = @(NewPopSize);
			set_popSize(popSizeDgt.integerValue = newSize);
		}
	}
	for (NSInteger i = 0; i < sliders.count; i ++)
	if ((num = dict[label_from_tag(i)]) != nil) {
		CGFloat newValue = num.doubleValue, orgValue = sliders[i].doubleValue;
		if (newValue != orgValue) {
			md[label_from_tag(i)] = @(orgValue);
			sliders[i].doubleValue = digits[i].doubleValue = newValue;
			set_param_value(i, newValue);
		}
	}
	for (NSInteger i = 0; i < NColors; i ++)
	if ((arr = dict[ColorNames[i]]) != nil) {
		MyRGB newValue = myRGB_from_array(arr);
		if (memcmp(&newValue, &Colors[i], sizeof(MyRGB)) != 0) {
			md[ColorNames[i]] = myRGB_to_array(Colors[i]);
			Colors[i] = newValue;
			colWels[i].color = myRGB_to_color(newValue);
			set_color_value(i, newValue);
		} 
	}
	if ((num = dict[keyShapeType]) != nil) {
		ShapeType newType = num.intValue;
		if (newType != shapeType) {
			md[keyShapeType] = @(shapeType);
			[shapePopUp selectItemAtIndex:newType];
			set_shape_type(newType);
		}
	}
	if ((num = dict[keyColorful]) != nil) {
		BOOL newValue = num.boolValue;
		if (newValue != Colorful) {
			md[keyColorful] = @(Colorful);
			colorfulCBox.state = newValue;
		}
	}
	if (md.count == 0) return;
	[self checkButtonEnabled];
	[undoMngr registerUndoWithTarget:self handler:^(PanelController *target) {
		[target setValuesFromDict:md];
	}];
}
- (void)setDefaultFromDict:(NSDictionary *)dict {
	NSNumber *numNew, *numOrg;
	NSArray<NSNumber *> *arrNew, *arrOrg;
	NSMutableDictionary *md = NSMutableDictionary.new;
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	if ((numNew = dict[keyPopSize]) != nil) {
		numOrg = [ud objectForKey:keyPopSize];
		NSInteger newSize = numNew.integerValue,
			orgSize = numOrg? numOrg.integerValue : PopSizeDefault;
		if (newSize != orgSize) {
			md[keyPopSize] = numOrg? numOrg : @(orgSize);
			if (newSize == PopSizeDefault) [ud removeObjectForKey:keyPopSize];
			else [ud setObject:numNew forKey:keyPopSize];
		}
	}
	for (NSInteger i = 0; i < sliders.count; i ++)
	if ((numNew = dict[label_from_tag(i)]) != nil) {
		numOrg = [ud objectForKey:label_from_tag(i)];
		CGFloat newValue = numNew.doubleValue, orgValue = numOrg? numOrg.doubleValue : 0.;
		if (newValue != orgValue) {
			md[label_from_tag(i)] = numOrg? numOrg : @(0.);
			if (newValue == 0.) [ud removeObjectForKey:label_from_tag(i)];
			else [ud setObject:numNew forKey:label_from_tag(i)];
		}
	}
	for (NSInteger i = 0; i < NColors; i ++)
	if ((arrNew = dict[ColorNames[i]]) != nil) {
		arrOrg = [ud objectForKey:ColorNames[i]];
		MyRGB newRGB = myRGB_from_array(arrNew),
			orgRGB = arrOrg? myRGB_from_array(arrOrg) : ColorDefault[i];
		if (memcmp(&newRGB, &orgRGB, sizeof(MyRGB)) != 0) {
			md[ColorNames[i]] = arrOrg;
			if (memcmp(&newRGB, &ColorDefault[i], sizeof(MyRGB)) == 0)
				[ud removeObjectForKey:ColorNames[i]];
			else [ud setObject:arrNew forKey:ColorNames[i]];
		} 
	}
	if ((numNew = dict[keyShapeType]) != nil) {
		ShapeType orgType = default_shapeType(), newType = (ShapeType)numNew.intValue;
		if (newType != orgType) {
			md[keyShapeType] = @(orgType);
			if (newType == ShapePaperPlane) [ud removeObjectForKey:keyShapeType];
			else [ud setObject:numNew forKey:keyShapeType];
		}
	}
	if ((numNew = dict[keyColorful]) != nil) {
		BOOL orgValue = default_colorful(), newValue = numNew.boolValue;
		if (newValue != orgValue) {
			md[keyColorful] = @(orgValue);
			if (newValue == YES) [ud removeObjectForKey:keyColorful];
			else [ud setBool:newValue forKey:keyColorful];
		}
	}
	NSObject *orgScr = default_screen(), *newScr = dict[keyFullScreenName];
	if (newScr != nil && !equal_screen_names(orgScr, newScr)) {
		md[keyFullScreenName] = orgScr? orgScr : @NO;
		if ([newScr isEqualTo:@NO])
			[ud removeObjectForKey:keyFullScreenName];
		else [ud setObject:newScr forKey:keyFullScreenName];
	}
	if (md.count == 0) return;
	[self checkButtonEnabled];
	[undoMngr registerUndoWithTarget:self handler:^(PanelController *target) {
		[target setDefaultFromDict:md];
	}];
}
- (void)setActionNameFromSender:(id)sender {
	if ([sender respondsToSelector:@selector(title)])
		undoMngr.actionName = [sender title];
}
- (IBAction)saveAsDefault:(id)sender {
	NSMutableDictionary *md = NSMutableDictionary.new;
	if (default_popSize() != NewPopSize) md[keyPopSize] = @(NewPopSize);
	for (NSInteger i = 0; i < sliders.count; i ++) {
		CGFloat orgValue = default_value(i), newValue = sliders[i].doubleValue;
		if (orgValue != newValue) md[label_from_tag(i)] = @(newValue);
	}
	for (NSInteger i = 0; i < NColors; i ++) {
		MyRGB orgRGB = default_color(i);
		if (memcmp(&orgRGB, &Colors[i], sizeof(MyRGB)) != 0)
			md[ColorNames[i]] = myRGB_to_array(Colors[i]);
	}
	if (shapeType != default_shapeType()) md[keyShapeType] = @(shapeType);
	if (Colorful != default_colorful()) md[keyColorful] = @(Colorful);
	if (!equal_screen_names(FullScreenName, default_screen()))
		md[keyFullScreenName] = FullScreenName? FullScreenName : @NO;
	if (md.count > 0) {
		[self setDefaultFromDict:md];
		[self setActionNameFromSender:sender];
	}
}
- (void)setValFromDictAsOpe:(NSDictionary *)dict sender:(id)sender {
	if (dict.count > 0) {
		[self setValuesFromDict:dict];
		[self setActionNameFromSender:sender];
	}
}
- (IBAction)revertToDefault:(id)sender {
	NSMutableDictionary *md = NSMutableDictionary.new;
	NSInteger newSize = default_popSize();
	if (newSize != NewPopSize) md[keyPopSize] = @(newSize);
	for (NSInteger i = 0; i < sliders.count; i ++) {
		CGFloat newVal = default_value(i);
		if (newVal != sliders[i].doubleValue) md[label_from_tag(i)] = @(newVal);
	}
	for (NSInteger i = 0; i < NColors; i ++) {
		MyRGB newRGB = default_color(i);
		if (memcmp(&newRGB, &Colors[i], sizeof(MyRGB)) != 0)
			md[ColorNames[i]] = myRGB_to_array(newRGB);
	}
	ShapeType newType = default_shapeType();
	if (shapeType != newType) md[keyShapeType] = @(newType);
	BOOL newVlaue = default_colorful();
	if (Colorful != newVlaue) md[keyColorful] = @(newVlaue);
	NSString *newScr = default_screen();
	if (!equal_screen_names(newScr, FullScreenName))
		md[keyFullScreenName] = newScr? newScr : @NO;
	[self setValFromDictAsOpe:md sender:sender];
}
- (IBAction)resetValues:(id)sender {
	NSMutableDictionary *md = NSMutableDictionary.new;
	if (NewPopSize != PopSizeDefault) md[keyPopSize] = @(PopSizeDefault);
	for (NSInteger i = 0; i < sliders.count; i ++)
		if (sliders[i].doubleValue != factory_default(i))
			md[label_from_tag(i)] = @(factory_default(i));
	for (NSInteger i = 0; i < NColors; i ++) {
		if (memcmp(&Colors[i], &ColorDefault[i], sizeof(MyRGB)) != 0)
			md[ColorNames[i]] = myRGB_to_array(ColorDefault[i]);
	}
	[self setValFromDictAsOpe:md sender:sender];
}
static UTType *doc_ut_type(void) {
	static UTType *utType = nil;
	static NSString *paramSetID = @"jp.ac.soka.unemi.BOIDS-GPU-params";
	if (utType == nil) utType = [UTType typeWithIdentifier:paramSetID];
	return utType;
}
- (NSDictionary *)dictFromParams {
	NSMutableDictionary *md = NSMutableDictionary.new;
	if (NewPopSize != PopSizeDefault) md[keyPopSize] = @(NewPopSize);
	for (NSInteger i = 0; i < sliders.count; i ++)
		if (sliders[i].doubleValue != factory_default(i))
			md[label_from_tag(i)] = @(sliders[i].doubleValue);
	for (NSInteger i = 0; i < NColors; i ++) {
		if (memcmp(&Colors[i], &ColorDefault[i], sizeof(MyRGB)) != 0)
			md[ColorNames[i]] = myRGB_to_array(Colors[i]);
	}
	return [NSDictionary dictionaryWithDictionary:md];
}
- (IBAction)saveValuesAsNewDoc:(id)sender {
	NSSavePanel *sp = NSSavePanel.savePanel;
	sp.allowedContentTypes = @[doc_ut_type()];
	[sp beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
		if (result != NSModalResponseOK) return;
		NSError *error;
		NSDictionary *dict = [self dictFromParams];
		NSData *data = [NSPropertyListSerialization dataWithPropertyList:dict format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
		if (data == nil) err_msg(error, NO);
		else if (![data writeToURL:sp.URL options:0 error:&error]) err_msg(error, NO);
	}];
}
- (IBAction)loadValuesFromDoc:(id)sender {
	NSOpenPanel *op = NSOpenPanel.openPanel;
	op.allowedContentTypes = @[doc_ut_type()];
	op.allowsMultipleSelection = NO;
	[op beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
		if (result != NSModalResponseOK) return;
		NSError *error;
		NSData *data = [NSData dataWithContentsOfURL:op.URL options:0 error:&error];
		if (data == nil) { err_msg(error, NO); return; }
		NSDictionary *dict = [NSPropertyListSerialization propertyListWithData:data
			options:0 format:NULL error:&error];
		if (dict == nil) err_msg(error, NO);
		else [self setValFromDictAsOpe:dict sender:sender];
	}];
}
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
	return undoMngr;
}
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	SEL action = menuItem.action;
	if (action == @selector(saveAsDefault:)) return saveBtn.enabled;
	if (action == @selector(revertToDefault:)) return revertBtn.enabled;
	if (action == @selector(resetValues:)) return resetBtn.enabled;
	if (action == @selector(saveValuesAsNewDoc:)) return saveAsBtn.enabled;
	return YES;
}
@end

@interface Parameters : NSDocument
@end

@implementation Parameters
- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError {
	NSDictionary *dict = [NSPropertyListSerialization
		propertyListWithData:data options:0 format:NULL error:outError];
	if (dict == nil) return NO;
	AppDelegate *appDlgt = NSApp.delegate;
	[appDlgt openPanel:nil];
	PanelController *pnlCntl = appDlgt.pnlCntl;
	[pnlCntl setValuesFromDict:dict];
	[pnlCntl windowWillReturnUndoManager:pnlCntl.window].actionName = @"Open";
	return YES;
}
@end
