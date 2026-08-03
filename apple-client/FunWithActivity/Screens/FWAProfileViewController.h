//
//  FWAProfileViewController.h
//  FunWithActivity
//
//  Tab 3 — Profile. UITableViewStyleInsetGrouped with two sections:
//
//    MEASUREMENTS — height, weight, birth date. Birth date is clearable
//      (tap to expand an inline date picker; a "Clear" button empties it
//      entirely) — clearing it is the data-minimisation demo beat.
//    DEVELOPER — a fault switch per provider, each with a mode selector
//      that stays disabled until its switch is on.
//
//  Every edit writes straight through to FWAAppState, which sets the dirty
//  flag the Recommendations tab reads on its next appearance.
//

#import <UIKit/UIKit.h>

@class FWAAppState;

NS_ASSUME_NONNULL_BEGIN

@interface FWAProfileViewController : UIViewController

- (instancetype)initWithAppState:(FWAAppState *)appState NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil
                          bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;

#if DEBUG
/// Headless-verification-only: expands the inline birth-date picker exactly
/// as tapping the row would. This project has no XCUITest/UI-automation
/// harness — demo states are driven by DEBUG launch arguments plus
/// screenshots, matching the rest of the codebase's verification
/// convention. Not compiled into Release.
- (void)debug_expandBirthDatePicker;
#endif

@end

NS_ASSUME_NONNULL_END
