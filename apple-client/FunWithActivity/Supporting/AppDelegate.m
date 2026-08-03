//
//  AppDelegate.m
//  FunWithActivity
//

#import "AppDelegate.h"
#import "FWAGRPCClient.h"
#import "FWAAppState.h"
#import "FWARecommendationsViewController.h"
#import "FWASourcesViewController.h"
#import "FWAProfileViewController.h"
#import "FWAAddSourceViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    // Manual, explicit construction — no reflection-heavy DI framework.
    // FWAGRPCClient reads its host from FWAServerConfig (single build-time
    // constant), unchanged from the single-screen app. FWAAppState is the
    // one new piece of shared state: Profile writes to it, Recommendations
    // reads/clears its dirty flag, Sources reads the statuses it records
    // after each fetch. One instance, shared by reference across all three
    // tabs — this is not persisted, it lives for the process's lifetime.
    FWAGRPCClient *grpcClient = [[FWAGRPCClient alloc] init];
    FWAAppState *appState = [[FWAAppState alloc] init];

    FWARecommendationsViewController *recommendationsVC =
        [[FWARecommendationsViewController alloc] initWithGRPCClient:grpcClient appState:appState];
    FWASourcesViewController *sourcesVC = [[FWASourcesViewController alloc] initWithAppState:appState];
    FWAProfileViewController *profileVC = [[FWAProfileViewController alloc] initWithAppState:appState];

    UINavigationController *recommendationsNav = [self navigationControllerWrapping:recommendationsVC
                                                                                 title:@"Recommendations"
                                                                             imageName:@"list.bullet.rectangle"];
    UINavigationController *sourcesNav = [self navigationControllerWrapping:sourcesVC
                                                                        title:@"Sources"
                                                                    imageName:@"server.rack"];
    UINavigationController *profileNav = [self navigationControllerWrapping:profileVC
                                                                        title:@"Profile"
                                                                    imageName:@"person.crop.circle"];

    UITabBarController *tabBarController = [[UITabBarController alloc] init];
    tabBarController.viewControllers = @[recommendationsNav, sourcesNav, profileNav];

    self.window.rootViewController = tabBarController;
    [self.window makeKeyAndVisible];

#if DEBUG
    [self applyDemoLaunchHooksWithAppState:appState
                            tabBarController:tabBarController
                                  sourcesNav:sourcesNav
                                  profileVC:profileVC];
#endif

    return YES;
}

#if DEBUG
// DEBUG-only launch-argument hooks for headless simulator verification —
// this project has no XCUITest/UI-automation harness (see
// FWAResultsViewController's history), so demo states are driven this way
// plus screenshots/os_log rather than simulated taps. Never compiled into
// Release.
- (void)applyDemoLaunchHooksWithAppState:(FWAAppState *)appState
                          tabBarController:(UITabBarController *)tabBarController
                                 sourcesNav:(UINavigationController *)sourcesNav
                                profileVC:(FWAProfileViewController *)profileVC {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // Pre-launch state mutation, applied before the first tab appears, so
    // the "fetch once on first appearance regardless" fetch already
    // reflects it.
    if ([defaults boolForKey:@"FWA_DEMO_CLEAR_BIRTHDATE"]) {
        appState.birthDate = nil;
    }

    // Deliberately does NOT switch tabs before the first fetch: tab 0
    // (Recommendations) must be the one that's initially selected so the
    // "fetch once on first appearance regardless" launch fetch actually
    // happens — a tab that's never been the selected one never loads its
    // view, so it never calls -viewWillAppear:. Switch AFTER giving that
    // fetch time to land, so Sources has real data to show instead of the
    // "waiting for the first fetch" placeholder.
    NSInteger selectTabAfterFetch = [defaults integerForKey:@"FWA_DEMO_SELECT_TAB_AFTER_FETCH"];
    if (selectTabAfterFetch > 0 && selectTabAfterFetch < (NSInteger)tabBarController.viewControllers.count) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            tabBarController.selectedIndex = selectTabAfterFetch;
        });
    }

    if ([defaults boolForKey:@"FWA_DEMO_EXPAND_BIRTHDATE_PICKER"]) {
        // 2.2s: after FWA_DEMO_SELECT_TAB_AFTER_FETCH's 1.5s switch to
        // Profile (when combined with it), so the table view is loaded
        // before this reaches into it.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [profileVC debug_expandBirthDatePicker];
        });
    }

    if ([defaults boolForKey:@"FWA_DEMO_PUSH_ADD_SOURCE"]) {
        BOOL alsoSubmit = [defaults boolForKey:@"FWA_DEMO_SUBMIT_ADD_SOURCE"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            FWAAddSourceViewController *addVC = [[FWAAddSourceViewController alloc] init];
            [sourcesNav pushViewController:addVC animated:NO];
            if (alsoSubmit) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [addVC debug_fillValidFormAndSubmit];
                });
            }
        });
    }

    // Proves the refetch-on-dirty-return mechanic end to end: after the
    // automatic first fetch (Recommendations is always tab 0, so it always
    // fetches on launch — 6 rows with the default birth date, both
    // providers reporting ok), mutate FWAAppState exactly as Profile would
    // — clear the birth date and/or enable a fault — then leave and return
    // to the Recommendations tab, exactly what a demo presenter's tab taps
    // do. If refetch-on-return were broken, the second screenshot would
    // still show the original 6-row, all-ok result.
    //
    // The fault is applied here (after the first fetch), not before it:
    // FWAAppState.providerNames only reflects the exact names the server
    // is checking against — "service1"/"service2" in production,
    // "service1-stub"/"service2-stub" against a local USE_STUB_PROVIDERS
    // run — once at least one response has been recorded. Applying it
    // before the first fetch would key the faults map off the un-resolved
    // default names, which happens to be correct in production (where the
    // defaults already match) but not against a local stub server. This
    // mirrors reality too: a real user cannot reach Profile's fault
    // switches before the tab-0 launch fetch has already happened.
    if ([defaults boolForKey:@"FWA_DEMO_REFETCH_SEQUENCE"]) {
        BOOL clearBirthDateOnReturn = [defaults boolForKey:@"FWA_DEMO_REFETCH_CLEAR_BIRTHDATE"];
        NSString *faultModeOnReturn = [defaults stringForKey:@"FWA_DEMO_REFETCH_FAULT_MODE"];
        NSInteger faultIndexOnReturn = [defaults integerForKey:@"FWA_DEMO_REFETCH_FAULT_INDEX"];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (clearBirthDateOnReturn) {
                appState.birthDate = nil;
            }
            if (faultModeOnReturn.length > 0) {
                [appState setFaultMode:faultModeOnReturn atIndex:faultIndexOnReturn];
                [appState setFaultEnabled:YES atIndex:faultIndexOnReturn];
            }
            tabBarController.selectedIndex = 2; // Profile — a real "leave the tab"
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                tabBarController.selectedIndex = 0; // back to Recommendations — triggers -viewWillAppear:

                NSInteger selectAfterRefetch = [defaults integerForKey:@"FWA_DEMO_SELECT_TAB_AFTER_REFETCH"];
                if (selectAfterRefetch > 0 && selectAfterRefetch < (NSInteger)tabBarController.viewControllers.count) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        tabBarController.selectedIndex = selectAfterRefetch;
                    });
                }
            });
        });
    }
}
#endif

// Every tab gets its own UINavigationController per §5.1 of the tabbed-UI
// design — pushes (e.g. Sources' "+" form) stay scoped to the tab they
// happened in, and each tab keeps its own back stack independent of the
// other two.
- (UINavigationController *)navigationControllerWrapping:(UIViewController *)rootVC
                                                     title:(NSString *)title
                                                 imageName:(NSString *)imageName {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:rootVC];
    nav.navigationBar.prefersLargeTitles = YES;
    nav.tabBarItem = [[UITabBarItem alloc] initWithTitle:title
                                                     image:[UIImage systemImageNamed:imageName]
                                                       tag:0];
    return nav;
}

@end
