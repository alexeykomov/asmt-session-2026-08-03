//
//  AppDelegate.m
//  FunWithActivity
//

#import "AppDelegate.h"
#import "FWAGRPCClient.h"
#import "FWAAppState.h"
#import "FWARecommendationsViewController.h"
#import "FWASourcesViewController.h"
#import "FWAChartsViewController.h"
#import "FWAProfileViewController.h"
#import "FWAAddSourceViewController.h"
#import "FWASourceDetailViewController.h"
#import "Recommendations.pbobjc.h"

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
    FWAChartsViewController *chartsVC =
        [[FWAChartsViewController alloc] initWithGRPCClient:grpcClient appState:appState];
    FWAProfileViewController *profileVC = [[FWAProfileViewController alloc] initWithAppState:appState];

    UINavigationController *recommendationsNav = [self navigationControllerWrapping:recommendationsVC
                                                                                 title:@"Recommendations"
                                                                             imageName:@"list.bullet.rectangle"];
    UINavigationController *sourcesNav = [self navigationControllerWrapping:sourcesVC
                                                                        title:@"Sources"
                                                                    imageName:@"server.rack"];
    UINavigationController *chartsNav = [self navigationControllerWrapping:chartsVC
                                                                       title:@"Charts"
                                                                   imageName:@"chart.bar"];
    UINavigationController *profileNav = [self navigationControllerWrapping:profileVC
                                                                        title:@"Profile"
                                                                    imageName:@"person.crop.circle"];

    UITabBarController *tabBarController = [[UITabBarController alloc] init];
    // Charts sits between Sources and Profile: it and Sources are both
    // read-only views of what the system knows, while Profile is where
    // things change. Inserting rather than appending moves Profile from
    // index 2 to 3 — the DEBUG launch hooks below select tabs by index, so
    // they were checked against this order rather than assumed unaffected.
    tabBarController.viewControllers = @[recommendationsNav, sourcesNav, chartsNav, profileNav];

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
// Tab indices, named rather than written as literals at each use. Charts was
// inserted third and moved Profile from 2 to 3; the literal `2` below then
// still compiled and still selected *a* tab, just the wrong one — a failure
// no build could catch and only a screenshot would reveal.
typedef NS_ENUM(NSUInteger, FWATabIndex) {
    FWATabIndexRecommendations = 0,
    FWATabIndexSources = 1,
    FWATabIndexCharts = 2,
    FWATabIndexProfile = 3,
};

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

    // Headless verification for FWASourceDetailViewController — same
    // reasoning as every other hook in this method (no XCUITest/UI-
    // automation harness in this project): pushes the exact same screen,
    // constructed the exact same way, that FWASourcesViewController's
    // -tableView:didSelectRowAtIndexPath: pushes on a real tap. Requires
    // FWA_DEMO_SELECT_TAB_AFTER_FETCH=1 in the same launch so Sources has
    // already switched in and a real fetch has already populated
    // appState.lastStatuses by the time this fires.
    if ([defaults boolForKey:@"FWA_DEMO_PUSH_SOURCE_DETAIL"]) {
        NSInteger detailIndex = [defaults integerForKey:@"FWA_DEMO_PUSH_SOURCE_DETAIL_INDEX"];
        // 5.0s: long enough to land after FWA_DEMO_REFETCH_SEQUENCE's own
        // ~3.6s of tab switches AND the real (network) second fetch it
        // triggers, not just the first launch fetch — this is the hook used
        // to verify the STATUS section against a genuinely degraded/skipped
        // status, which only exists after that sequence completes.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // Force Sources to have loaded its view at least once first, so
            // its navigationItem.title ("Sources", set in -viewDidLoad) is
            // there for the pushed detail screen's back button — pushing
            // onto a tab's nav stack does not itself trigger that tab's
            // view to load if it has never been the selected tab.
            tabBarController.selectedIndex = FWATabIndexSources;
            NSArray<ProviderStatus *> *statuses = appState.lastStatuses;
            if (detailIndex >= 0 && detailIndex < (NSInteger)statuses.count) {
                ProviderStatus *status = statuses[detailIndex];
                FWASourceDetailViewController *detailVC =
                    [[FWASourceDetailViewController alloc] initWithProviderName:status.name status:status];
                [sourcesNav pushViewController:detailVC animated:NO];
            }
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
            tabBarController.selectedIndex = FWATabIndexProfile; // a real "leave the tab"
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                tabBarController.selectedIndex = FWATabIndexRecommendations; // triggers -viewWillAppear:

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
