//Copyright 2005 Dominic Yu. Some rights reserved.
//This work is licensed under the Creative Commons
//Attribution-NonCommercial-ShareAlike License. To view a copy of this
//license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/ or send
//a letter to Creative Commons, 559 Nathan Abbott Way, Stanford,
//California 94305, USA.

#include "stdlib.h"

#import "SlideshowWindow.h"
#import <Carbon/Carbon.h>
#import "DYCarbonGoodies.h"
#import "NSStringDYBasePathExtension.h"
#import "CreeveyController.h"

@interface SlideshowWindow (Private)

//- (void)displayImage;
- (void)jump:(int)n;
- (void)jumpTo:(int)n;
- (void)setTimer:(NSTimeInterval)s;
- (void)runTimer;
- (void)killTimer;
- (void)updateInfoFld;
- (void)updateExifFld;

- (void)saveZoomInfo;

// cat methods
- (void)displayCats;
- (void)assignCat:(short int)n toggle:(BOOL)toggle;

// cache methods
- (NSImage *)loadFromCache:(NSString *)s;
- (void)cacheAndDisplay:(NSString *)s;


@end

@implementation SlideshowWindow

+ (void)initialize {
	srandom((unsigned long)time(NULL));
}

#define MAX_CACHED 15
// MAX_CACHED must be bigger than the number of items you plan to have cached!
#define MAX_REPEATING_CACHED 6
// when key is held down, max to cache before skipping over

// this is the designated initializer
- (id)initWithContentRect:(NSRect)r styleMask:(unsigned int)m backing:(NSBackingStoreType)b defer:(BOOL)d {
	// full screen window, force it to be NSBorderlessWindowMask
	if (self = [super initWithContentRect:r styleMask:NSBorderlessWindowMask backing:b defer:d]) {
		filenames = [[NSMutableArray alloc] init];
		rotations = [[NSMutableDictionary alloc] init];
		zooms = [[NSMutableDictionary alloc] init];
		imgCache = [[DYImageCache alloc] initWithCapacity:MAX_CACHED];
		
 		[self setBackgroundColor:[NSColor blackColor]];
		[self setOpaque:NO];
		currentIndex = -1;//blurr=8;
   }
    return self;
}


- (void)awakeFromNib {
	imgView = [[DYImageView alloc] initWithFrame:NSZeroRect];
	[self setContentView:imgView]; // image now fills entire window
	[imgView release]; // the prev line retained it
	
	infoFld = [[NSTextField alloc] initWithFrame:NSMakeRect(0,0,360,20)];
	[imgView addSubview:infoFld]; [infoFld release];
	[infoFld setBackgroundColor:[NSColor grayColor]];
	[infoFld setBezeled:NO];
	[infoFld setEditable:NO];
	
	catsFld = [[NSTextField alloc] initWithFrame:NSZeroRect];
	[imgView addSubview:catsFld]; [catsFld release];
	[catsFld setBackgroundColor:[NSColor grayColor]];
	[catsFld setBezeled:NO];
	[catsFld setEditable:NO]; // **
	[catsFld setHidden:YES];
	
	NSSize s = [self frame].size;
	NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(s.width-360,0,360,s.height-20)];
	[imgView addSubview:sv]; [sv release];
	[sv setAutoresizingMask:NSViewHeightSizable | NSViewMinXMargin];
	
	exifFld = [[NSTextView alloc] initWithFrame:NSMakeRect(0,0,[sv contentSize].width,20)];
	[sv setDocumentView:exifFld]; [exifFld release];
	[exifFld setAutoresizingMask:NSViewHeightSizable | NSViewWidthSizable];

	[sv setDrawsBackground:NO];
	[sv setHasVerticalScroller:YES];
	[sv setVerticalScroller:[[[NSScroller alloc] init] autorelease]];
	[[sv verticalScroller] setControlSize:NSSmallControlSize];
	[sv setAutohidesScrollers:YES];
	//[exifFld setEditable:NO];
	[exifFld setDrawsBackground:NO];
	[exifFld setSelectable:NO];
	//[exifFld setVerticallyResizable:NO];
	[sv setHidden:YES];
}

- (void)dealloc {
	[filenames release];
	[rotations release];
	[zooms release];
	[imgCache release];
	[helpFld release];
	[super dealloc];
}

- (void)setCats:(NSMutableSet **)newCats {
    cats = newCats;
}

// must override this for borderless windows
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }

// start/end stuff
- (void)setFilenames:(NSArray *)files {
	[filenames removeAllObjects];
	[filenames addObjectsFromArray:files];
}

- (void)setBasePath:(NSString *)s {
	if (currentIndex != -1)
		[self saveZoomInfo]; // in case we're called without endSlideshow being called
	
	[basePath release];
	if ([s characterAtIndex:[s length]-1] != '/')
		basePath = [[s stringByAppendingString:@"/"] retain];
	else
		basePath = [s copy];
}

- (NSString *)currentShortFilename {
	NSString *s = [filenames objectAtIndex:currentIndex];
	return [s stringByDeletingBasePath:basePath];
}

- (void)endSlideshow {
	[self saveZoomInfo];

	lastIndex = currentIndex;
	currentIndex = -1;
	[self killTimer];
	[self orderOut:nil];
	
	[imgCache abortCaching];
}

- (void)startSlideshow {
	[self startSlideshowAtIndex:-1]; // to distinguish from 0, for random mode
}
- (void)startSlideshowAtIndex:(int)startIndex {
	if ([filenames count] == 0) {
		NSBeep();
		return;
	}
	
	screenRect = [[NSScreen mainScreen] frame];
	[imgCache setBoundingSize:screenRect.size];
	// ** caching issues?
	// if oldBoundingSize != or < newSize, delete cache

	// this may need to change as screen res changes
	// we assume user won't change screen resolution during a show
	// ** but they might!
	
	[self setContentSize:screenRect.size];
	[self setFrameOrigin:screenRect.origin];
	[catsFld setFrame:NSMakeRect(0,[imgView bounds].size.height-20,300,20)];
	// ** OR set springiness on awake
	
	
	if (randomMode) {
		unsigned i = [filenames count];
		if (startIndex != -1)
			// save selected image at the end
			[filenames exchangeObjectAtIndex:startIndex withObjectAtIndex:--i];
		while (--i)
			[filenames exchangeObjectAtIndex:i withObjectAtIndex:random()%(i+1)];
		if (startIndex != -1) {
			// now put it at the beginning
			[filenames exchangeObjectAtIndex:0 withObjectAtIndex:[filenames count]-1];
			startIndex = 0;
		}
	}
	if (startIndex == -1) startIndex = 0;
	currentIndex = startIndex;
	[self setTimer:timerIntvl]; // reset the timer, in case running
	if (helpFld) [helpFld setHidden:YES];
	[exifFld setString:@""];
	[imgCache beginCaching];
	[imgView setImage:nil];
	[self displayImage];
	[self makeKeyAndOrderFront:nil];
	// ordering front seems to reset the cursor, so force it again
	[imgView setCursor];
}

- (void)becomeMainWindow { // need this when switching apps
	//[self bringToForeground];
	//HideMenuBar(); // in Carbon
	//OSStatus Error = 
	SetSystemUIMode(kUIModeAllHidden, kUIOptionAutoShowMenuBar);
    //if (Error != noErr) NSLog(@"Error couldn't set SystemUIMode: %ld", (long)Error);
	[super becomeMainWindow];
}

- (void)resignMainWindow {
	SetSystemUIMode(kUIModeNormal, 0);	
	[super resignMainWindow];
}

- (void)sendToBackground {
	//[self setLevel:NSNormalWindowLevel-1];
}

- (void)bringToForeground {
	//[self setLevel:NSNormalWindowLevel]; //**debugging
//	[self setLevel:NSFloatingWindowLevel];//CGShieldingWindowLevel()];//NSMainMenuWindowLevel+1
}

#pragma mark timer stuff
// setTimer
// sets the interval between slide show advancing.
// set to 0 to stop.
- (void)setTimer:(NSTimeInterval)s {
	timerIntvl = s;
	if (s)
		[self runTimer];
	else
		[self killTimer];
}

// a method for the public to call; added for the pref panel
- (void)setAutoadvanceTime:(NSTimeInterval)s {
	if (currentIndex == -1)
		timerIntvl = s;
	else
		[self setTimer:s];
}


- (void)runTimer {
	[self killTimer]; // always remove the old timer
	if (loopMode || currentIndex+1 < [filenames count]) {
		//NSLog(@"scheduling timer from %d", currentIndex);
		autoTimer = [NSTimer
scheduledTimerWithTimeInterval:timerIntvl
						target:self
					  selector:@selector(nextTimer:)
					  userInfo:nil repeats:NO];
	}
}

- (void)killTimer {
	[autoTimer invalidate]; autoTimer = nil;
}

- (void)pauseTimer {
	[self killTimer];
	timerPaused = YES;
	if (hideInfoFld) [infoFld setHidden:NO];
	[self updateInfoFld];
}

- (void)nextTimer:(NSTimer *)t {
	//NSLog(@"timer fired!");
	autoTimer = nil; // so another thread won't send a message to a stale timer obj
	[self jump:1]; // works with loop mode
}

#pragma mark display stuff
- (float)calcZoom:(NSSize)sourceSize {
	// calc here b/c larger images have already been cached & shrunk!
	NSRect boundsRect = [imgView bounds];
	int rotation = [imgView rotation];
	float tmp;
	if (rotation == 90 || rotation == -90) {
		tmp = boundsRect.size.width;
		boundsRect.size.width = boundsRect.size.height;
		boundsRect.size.height = tmp;
	}
	
	if (![imgView scalesUp]
		&& sourceSize.width <= boundsRect.size.width
		&& sourceSize.height <= boundsRect.size.height)
	{
		return 1;
	} else {
		float w_ratio, h_ratio;
		w_ratio = boundsRect.size.width/sourceSize.width;
		h_ratio = boundsRect.size.height/sourceSize.height;
		return w_ratio < h_ratio ? w_ratio : h_ratio;
	}
}

- (void)updateExifFld {
	NSMutableAttributedString *attStr;
	attStr = Fileinfo2EXIFString([filenames objectAtIndex:currentIndex],
								 imgCache,moreExif,YES);
	NSRange r = NSMakeRange(0,[attStr length]);
	NSShadow *shdw = [[[NSShadow alloc] init] autorelease];
	[shdw setShadowColor:[NSColor blackColor]];
	[shdw setShadowBlurRadius:7]; // 7 or 8 is good
	[attStr addAttribute:NSShadowAttributeName
				   value:shdw
				   range:r];
//	[attStr addAttribute:NSStrokeColorAttributeName
//				   value:[NSColor blackColor]
//				   range:r];
//	[attStr addAttribute:NSStrokeWidthAttributeName
//				   value:[NSNumber numberWithFloat:-3]
//				   range:r];
//	[attStr addAttribute:NSExpansionAttributeName
//				   value:[NSNumber numberWithFloat:0.1]
//				   range:r];
	[exifFld replaceCharactersInRange:NSMakeRange(0,[[exifFld string] length])
							  withRTF:[attStr RTFFromRange:NSMakeRange(0,[attStr length])
										documentAttributes:nil]];
	[exifFld setTextColor:[NSColor whiteColor]];
	//NSLog(@"%i",blurr);
}


// display image number "currentIndex"
// if it's not cached, say "Loading" and spin off a thread to cache it
- (void)updateInfoFldWithRotation:(int)r {
	DYImageInfo *info = [imgCache infoForKey:[filenames objectAtIndex:currentIndex]];
	id dir;
	switch (r) {
		case 90: dir = NSLocalizedString(@" left", @""); break;
		case -90: dir = NSLocalizedString(@" right", @""); break;
		default: dir = @"";
	}
	if (r < 0) r = -r;
	float zoom = [imgView zoomMode] ? [imgView zoomF] : [self calcZoom:info->pixelSize];
	[infoFld setStringValue:[NSString stringWithFormat:@"[%i/%i%@] %@ - %@%@ - %@%@",
		currentIndex+1, [filenames count],
		r ? [NSString stringWithFormat:
			NSLocalizedString(@" rotated%@ %i%C", @""), dir, r, 0xb0] : @"", //degrees
		[self currentShortFilename],
		[info pixelSizeAsString],
		(zoom != 1.0 || [imgView zoomMode]) ? [NSString stringWithFormat:
			@" @ %.0f%%", zoom*100] : @"",
		FileSize2String(info->fileSize),
		timerIntvl && timerPaused ? [NSString stringWithFormat:@" %@(%.1g%@) %@",
			NSLocalizedString(@"Auto-advance", @""),
			timerIntvl,
			NSLocalizedString(@"seconds", @""),
			NSLocalizedString(@"PAUSED", @"")]
								  : @""]];
//	[infoFld setNeedsDisplay:YES];
	[infoFld sizeToFit];
//	[infoFld setNeedsDisplay:YES];
	[imgView setNeedsDisplay:YES]; // **
}

- (void)updateInfoFld {
	[self updateInfoFldWithRotation:[imgView rotation]];
}

- (void)redisplayImage {
	if (currentIndex == -1) return;
	id theFile = [filenames objectAtIndex:currentIndex];
	[imgCache removeImageForKey:theFile];
	[zooms removeObjectForKey:theFile]; // don't forget to reset the zoom/rotation!
	[rotations removeObjectForKey:theFile];
	[self displayImage];
}

- (void)uncacheImage:(NSString *)s {
	[imgCache removeImageForKey:s];
	[zooms removeObjectForKey:s];
	[rotations removeObjectForKey:s];
	if ((currentIndex != -1) && [s isEqualToString:[filenames objectAtIndex:currentIndex]])
		[self displayImage];
}

- (void)displayImage {
	if (currentIndex == -1) return; // in case called after slideshow ended
									// not necessary if s/isActive/isKeyWindow/
	NSString *theFile = [filenames objectAtIndex:currentIndex];
	NSImage *img = [self loadFromCache:theFile];
	[self displayCats];
	if (img) {
		//NSLog(@"displaying %d", currentIndex);
		NSNumber *rot = [rotations objectForKey:theFile];
		DYImageViewZoomInfo *zoomInfo = [zooms objectForKey:theFile];
		int r = rot ? [rot intValue] : 0;
		if (hideInfoFld) [infoFld setHidden:YES]; // this must happen before setImage, for redraw purposes
		[imgView setImage:img];
		if (r) [imgView setRotation:r];
		// ** see keyDown for specifics
		// if zoomed in, we need to set a different image
		// here, copy-pasted from keyDown
		DYImageInfo *info = [imgCache infoForKey:[filenames objectAtIndex:currentIndex]];
		if (zoomInfo || ([imgView showActualSize] &&
						 !(info->pixelSize.width < [imgView bounds].size.width &&
						   info->pixelSize.height < [imgView bounds].size.height))) {
			[imgView setImage:[[[NSImage alloc] initByReferencingFile:ResolveAliasToPath(theFile)] autorelease]
					   zoomIn:2];
			if (zoomInfo) [imgView setZoomInfo:zoomInfo];
		}
		[self updateInfoFldWithRotation:r];
		if (![[exifFld enclosingScrollView] isHidden]) [self updateExifFld];
		if (timerIntvl) [self runTimer];
	} else {
		if (hideInfoFld) [infoFld setHidden:NO];
		[infoFld setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Loading [%i/%i] %@...", @""),
			currentIndex+1, [filenames count], [self currentShortFilename]]];
		[infoFld sizeToFit];
		return;
	}
	if (keyIsRepeating) return; // don't bother precaching if we're fast-forwarding anyway

	if ([self isMainWindow] && ![imgView dragMode])
		[NSCursor setHiddenUntilMouseMoves:YES];

	int i;
	for (i=1; i<=2; i++) {
		if (currentIndex+i >= [filenames count])
			break;
		[imgCache cacheFileInNewThread:[filenames objectAtIndex:currentIndex+i]];
	}
}

- (void)jump:(int)n { // go forward n pics (negative numbers go backwards)
	if (n < 0)
		[self setTimer:0]; // going backwards stops auto-advance
	else // could get rid of 'else' b/c going backwards makes timerPaused irrelevant
		timerPaused = NO; // going forward unpauses auto-advance
	if ((n > 0 && currentIndex+1 == [filenames count]) || (n < 0 && currentIndex == 0)){
		if (loopMode)
			[self jumpTo:n<0 ? [filenames count]-1 : 0];
		else
			NSBeep();
		return;
	}
	[self jumpTo:currentIndex+n];
}

- (void)jumpTo:(int)n {
	//NSLog(@"jumping to %d", n);
	[self killTimer];
	// we rely on this only being called when changing pics, not at startup
	[self saveZoomInfo];
	// above code is repeated in endSlideshow, setBasePath
	
	currentIndex = n < 0 ? 0 : n >= [filenames count] ? [filenames count] - 1 : n;
	[self displayImage];
}

- (void)saveZoomInfo {
	if ([imgView zoomInfoNeedsSaving])
		[zooms setObject:[imgView zoomInfo]
				  forKey:[filenames objectAtIndex:currentIndex]];
}

- (void)setRotation:(int)n {
	n = [imgView addRotation:n];
	[rotations setObject:[NSNumber numberWithInt:n]
				  forKey:[filenames objectAtIndex:currentIndex]];
	[self updateInfoFldWithRotation:n];
}

- (void)toggleExif {
	[[exifFld enclosingScrollView] setHidden:![[exifFld enclosingScrollView] isHidden]];
	if (![[exifFld enclosingScrollView] isHidden])
		[self updateExifFld];
}

- (void)toggleHelp {
	if (!helpFld) {
		helpFld = [[NSTextView alloc] initWithFrame:NSZeroRect]; //NSMakeRect(0,0,310,265)
		[[self contentView] addSubview:helpFld]; [helpFld release];
//		[helpFld setHorizontallyResizable:YES]; // NO by default
//		[helpFld setVerticallyResizable:NO]; // YES by default
//		[helpFld sizeToFit]; //doesn't do anything?
		if (![helpFld readRTFDFromFile:
			[[NSBundle mainBundle] pathForResource:@"creeveyhelp" ofType:@"rtf"]])
			NSLog(@"couldn't load cheat sheet!");
		[helpFld setBackgroundColor:[NSColor lightGrayColor]];
		[helpFld setSelectable:NO];
//		NSLayoutManager *lm = [helpFld layoutManager];
//		NSRange rnge = [lm glyphRangeForCharacterRange:NSMakeRange(0,[[helpFld textStorage] length])
//								  actualCharacterRange:NULL];
//		NSSize s = [lm boundingRectForGlyphRange:rnge
//								 inTextContainer:[lm textContainerForGlyphAtIndex:0
//																   effectiveRange:NULL]].size;
//			//[[helpFld textStorage] size];
//		NSLog(NSStringFromRange(rnge));
		NSSize s = [[helpFld textStorage] size];
		NSRect r = NSMakeRect(0,0,s.width+10,s.height);
		// width must be bigger than text, or wrappage will occur
		s = [[self contentView] frame].size;
		r.origin.x = s.width - r.size.width - 50;
		r.origin.y = s.height - r.size.height - 55;
		[helpFld setFrame:NSIntegralRect(r)];
		return;
	}
	[helpFld setHidden:![helpFld isHidden]];
}

#pragma mark event stuff
// Here's the bulk of our user interface, all keypresses
- (void)keyUp:(NSEvent *)e {
	if (keyIsRepeating) {
		keyIsRepeating = 0;
		switch ([[e characters] characterAtIndex:0]) {
			case ' ':
			case NSRightArrowFunctionKey:
			case NSDownArrowFunctionKey:
			case NSLeftArrowFunctionKey:
			case NSUpArrowFunctionKey:
			case NSPageUpFunctionKey:
			case NSPageDownFunctionKey:
				[self displayImage];
				break;
			default:
				break;
		}
	}
}
- (void)keyDown:(NSEvent *)e {
	unichar c = [[e characters] characterAtIndex:0];
	if (c >= '1' && c <= '9') {
		if (([e modifierFlags] & NSNumericPadKeyMask) != 0 && [imgView zoomMode]) {
			if (c == '5') {
				NSBeep();
			} else {
				char x,y;
				c -= '0';
				if (c<=3) y = 1; else if (c>=7) y = -1; else y = 0;
				if (c%3 == 0) x = -1; else if (c%3 == 1) x = 1; else x=0;
				[imgView fakeDragX:([imgView bounds].size.width/2)*x
								 y:([imgView bounds].size.height/2)*y];
			}
		} else {
			if (timerIntvl == 0 || timerPaused) [self jump:1];
			[self setTimer:c - '0'];
		}
		return;
	}
	if (c == '0') {
		[self setTimer:0];
		[self updateInfoFld];
		return;
	}
	if (c >= NSF1FunctionKey && c <= NSF12FunctionKey) {
		[self assignCat:c - NSF1FunctionKey + 1
				 toggle:([e modifierFlags] & NSCommandKeyMask) != 0];
		//NSLog(@"got cat %i", c - NSF1FunctionKey + 1);
		return;
	}
	if ([e isARepeat] && keyIsRepeating < MAX_REPEATING_CACHED) {
		keyIsRepeating++;
	}
	DYImageInfo *obj;
	switch (c) {
		case '!':
			[self setTimer:0.5];
			break;
		case '@':
			[self setTimer:1.5];
			break;
		case ' ':
			if (timerIntvl && autoTimer) {
				//[self setTimer:0];
				[self pauseTimer];
				break; // pause slideshow only
			}
			// otherwise advance
		case NSRightArrowFunctionKey:
		case NSDownArrowFunctionKey:
			[self jump:1];
			break;
		case NSLeftArrowFunctionKey:
		case NSUpArrowFunctionKey:
			[self jump:-1];
			break;
		case NSHomeFunctionKey:
			[self jump:-currentIndex]; // <0 stops auto-advance
			break;
		case NSEndFunctionKey:
			[self jumpTo:[filenames count]-1];
			break;
		case NSPageUpFunctionKey:
			[self jump:-10];
			break;
		case NSPageDownFunctionKey:
			[self jump:10];
			break;
		case 'q':
		case '\x1b': // escape
			[self endSlideshow];
			break;
		case 'i':
			// cycles three ways: info, info + exif, none
			hideInfoFld = ![infoFld isHidden] && ![[exifFld enclosingScrollView] isHidden];
			if (![infoFld isHidden])
				[self toggleExif];
			[infoFld setHidden:hideInfoFld]; // 10.3 or later!
			break;
		case 'h':
		case '?':
		case '/':
		case NSHelpFunctionKey: // doesn't work, trapped at a higher level?
			[self toggleHelp];
			break;
		case 'I':
			if ([[exifFld enclosingScrollView] isHidden]) {
				moreExif = YES;
				hideInfoFld = NO;
				[self toggleExif];
				[infoFld setHidden:NO];
			} else {
				moreExif = !moreExif;
				[self updateExifFld];
			}
			break;
//		case 'e':
//			[self toggleExif];
//			break;
//		case 'j': blurr--; [self updateExifFld]; break;
//		case 'k': blurr++; [self updateExifFld]; break;
		case 'l':
			[self setRotation:90];
			break;
		case 'r':
			[self setRotation:-90];
			break;
		case '=':
			//if ([imgView showActualSize])
			//	[zooms removeObjectForKey:[filenames objectAtIndex:currentIndex]];
			// actually, '=' doesn't center the pic, so this is wrong
			// if you zoom or move a pic while in actualsize mode, you're basically stuck with a non-default zoom
			// intentional fall-through to next cases
		case '+':
		case '-':
			if (obj = [imgCache infoForKey:[filenames objectAtIndex:currentIndex]]) {
				if (obj->image == [imgView image]
					&& !NSEqualSizes(obj->pixelSize,[obj->image size])) { // cached image smaller than orig
					[imgView setImage:[[[NSImage alloc] initByReferencingFile:
						ResolveAliasToPath([filenames objectAtIndex:currentIndex])] autorelease]
							   zoomIn:c == '=' ? 2 : c == '+'];
				} else {
					if (c == '+') [imgView zoomIn];
					else if (c == '-') [imgView zoomOut];
					else [imgView zoomActualSize];
				}
				[self updateInfoFld];
			}
			// can't save zooms here, save when leaving the pict; see jumpTo
			// for important comments
			break;
		case '*':
			[imgView zoomOff];
			if (![imgView showActualSize])
				[zooms removeObjectForKey:[filenames objectAtIndex:currentIndex]];
			[self updateInfoFld];
			break;
		default:
			//NSLog(@"%x",c);
			[super keyDown:e];
	}
}

- (BOOL)performKeyEquivalent:(NSEvent *)e {
	unichar c = [[e characters] characterAtIndex:0];
	//NSLog([e charactersIgnoringModifiers]);
	//NSLog([e characters]);
	// charactersIgnoringModifiers is 10.4 or later, and doesn't play well with Dvorak Qwerty-cmd
	DYImageInfo *obj;
	switch (c) {
		case '=':
			if (!([e modifierFlags] & NSNumericPadKeyMask))
				c = '+';
			// intentional fall-through
		case '+':
		case '-':
			// ** code copied from keyDown
			if (obj = [imgCache infoForKey:[filenames objectAtIndex:currentIndex]]) {
				if (obj->image == [imgView image]
					&& !NSEqualSizes(obj->pixelSize,[obj->image size])) {  // cached image smaller than orig
					[imgView setImage:[[[NSImage alloc] initByReferencingFile:
						ResolveAliasToPath([filenames objectAtIndex:currentIndex])] autorelease]
							   zoomIn:c == '=' ? 2 : c == '+'];
				} else {
					if (c == '+') [imgView zoomIn];
					else if (c == '-') [imgView zoomOut];
					else [imgView zoomActualSize];
				}
				[self updateInfoFld];
			}
			return YES;
		default:
			return [super performKeyEquivalent:e];
	}
}


// mouse control added for 1.2.2 (2006 Aug)

- (void)mouseDown:(NSEvent *)e {
	if ([imgView dragMode])
		return;
	
	mouseDragged = YES; // prevent the following mouseUp from advancing twice
	    // this would happen if it was zoomed in
	if ([e clickCount] == 1)
		[self jump:1];
	else if ([e clickCount] == 2)
		[self endSlideshow];
}

// while zoomed, wait until mouseUp to advance/end
- (void)mouseUp:(NSEvent *)e {
	if (![imgView dragMode])
		return;
	if (mouseDragged)
		return;
	
	if ([e clickCount] == 1)
		[self jump:1];
	else if ([e clickCount] == 2)
		[self endSlideshow];
}

- (void)rightMouseDown:(NSEvent *)e {
	[self jump:-1];
}

- (void)sendEvent:(NSEvent *)e {
	NSEventType t = [e type];

	// override to send right clicks to self
	if (t == NSRightMouseDown)	{
		[self rightMouseDown:e];
		return;
	}
	// but trapping help key here doesn't work

	if (t == NSLeftMouseDragged) {
		mouseDragged = YES;
	} else if (t == NSLeftMouseDown) {
		mouseDragged = NO; // reset this on mouseDown, not mouseUp (too early)
		// or wait til after call to super
	}
	[super sendEvent:e];
}

- (void)scrollWheel:(NSEvent *)e {
	float y = [e deltaY];
	int sign = y < 0 ? 1 : -1;
	[self jump:sign*(floor(fabs(y)/7.0)+1)];
}

	
// cache stuff

- (NSImage *)loadFromCache:(NSString *)s {
	NSImage *img = [imgCache imageForKey:s];
	if (img)
		return img;
	//NSLog(@"%d not cached yet, now loading", n);
	if (keyIsRepeating < MAX_REPEATING_CACHED || currentIndex == 0 || currentIndex == [filenames count]-1)
		[NSThread detachNewThreadSelector:@selector(cacheAndDisplay:)
								 toTarget:self withObject:s];
	return nil;
}

- (void)cacheAndDisplay:(NSString *)s { // ** roll this into imagecache?
	if (currentIndex == -1) return; // in case slideshow ended before thread started
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[imgCache cacheFile:s]; // this operation takes time...
	if (currentIndex != -1 && [[filenames objectAtIndex:currentIndex] isEqualToString:s]) {
		//NSLog(@"cacheAndDisplay now displaying %@", idx);
		[self performSelectorOnMainThread:@selector(displayImage) // requires 10.2
							   withObject:nil waitUntilDone:NO];
		//[self displayImage];
		//if (autoTimer) [[NSRunLoop currentRunLoop] run];
		// we must run the runLoop for the timer b/c we're in a separate thread
	} /*else {
		NSLog(@"cacheAndDisplay aborted %@", idx);
		// the user hit next or something, we don't need this anymore		
	} */
	[pool release];
}

// giving access to outsiders
- (BOOL)isActive {
	return currentIndex != -1;
}
- (int)currentIndex {
	return currentIndex == -1 ? lastIndex : currentIndex;
}
- (NSString *)currentFile {
	//if (currentIndex == -1) return nil;
	return [filenames objectAtIndex:[self currentIndex]];
}

- (BOOL)currentImageLoaded {
	NSString *s = [self currentFile];
	return [imgCache infoForKey:s] != nil;
}

- (void)removeImageForFile:(NSString *)s {
	[imgCache removeImageForKey:s];
	[filenames removeObject:s];
	if (currentIndex == [filenames count]) currentIndex--;
	if (currentIndex == -1) {
		// no more images to display!
		[self endSlideshow];
		return;
	}
	[self displayImage]; // reload at the current index
}

- (void)unsetFilename:(NSString *)s { // maybe rename fileWasDeleted, to match creeveywindows?
	int n = [filenames indexOfObject:s];
	[filenames removeObjectAtIndex:n];
	[imgCache removeImageForKey:s];
	
	if (n < currentIndex || currentIndex == [filenames count])
		currentIndex--;
	if (currentIndex == -1) {
		// no more images to display!
		[self endSlideshow];
		return;
	}
	[self displayImage];
}


#pragma mark cat methods
- (void)displayCats {
	NSMutableArray *labels = [NSMutableArray arrayWithCapacity:1];
	NSString *s = [filenames objectAtIndex:currentIndex];
	short int i;
	for (i=0; i<NUM_FNKEY_CATS; ++i) {
		if ([cats[i] containsObject:s])
			[labels addObject:[NSString stringWithFormat:NSLocalizedString(@"Group %i", @""), i+2]];
	}
	if ([labels count]) {
		[catsFld setStringValue:[labels componentsJoinedByString:@", "]];
		[catsFld sizeToFit];
		[catsFld setHidden:NO];
	} else {
		[catsFld setHidden:YES];
	}
}

- (void)assignCat:(short int)n toggle:(BOOL)toggle{
	if (n==1) {
		short int i;
		for (i=0; i<NUM_FNKEY_CATS; ++i)
			[cats[i] removeObject:[filenames objectAtIndex:currentIndex]];
	} else {
		id s = [filenames objectAtIndex:currentIndex];
		if (toggle && [cats[n-2] containsObject:s])
			[cats[n-2] removeObject:s];
		else
			[cats[n-2] addObject:s];
		if (toggle)
			[imgView setNeedsDisplayInRect:[catsFld frame]]; // in case the field shrinks
	}
	[self displayCats];
}


#pragma mark menu methods
- (BOOL)validateMenuItem:(id <NSMenuItem>)menuItem {
	if ([menuItem tag] == 3) // Loop
		return YES;
	if ([menuItem tag] == 8) // Scale Up
		return YES;
	if ([menuItem tag] == 9) // Actual Size
		return YES;
	if ([menuItem tag] == 7) // random
		return ![self isActive];
	// check if the item's menu is the slideshow menu
	return [[menuItem menu] itemWithTag:3] ? [self isActive]
										   : [super validateMenuItem:menuItem];
}

- (IBAction)endSlideshow:(id)sender {
	[self endSlideshow];
}

- (IBAction)toggleLoopMode:(id)sender {
	BOOL b = ![sender state];
	[sender setState:b];
	loopMode = b;
}
- (IBAction)toggleCheatSheet:(id)sender {
	[self toggleHelp];
	//[sender setState:![helpFld isHidden]]; // ** wrong if user hits 'h'
}
- (IBAction)toggleScalesUp:(id)sender {
	BOOL b = ![sender state];
	[sender setState:b];
	[imgView setScalesUp:b];
	if (currentIndex != -1)
		[self updateInfoFld];
}
- (IBAction)toggleRandom:(id)sender {
	BOOL b = ![sender state];
	[sender setState:b];
	randomMode = b;
}
- (IBAction)toggleShowActualSize:(id)sender {
	BOOL b = ![sender state];
	// save zoomInfo, if any, BEFORE changing the vars
	if (currentIndex != -1) {
		[self killTimer]; // ** why?
		[self saveZoomInfo];
	}
	// then change vars and re-display
	[sender setState:b];
	[imgView setShowActualSize:b];
	if (currentIndex != -1) [self displayImage]; 
}

@end