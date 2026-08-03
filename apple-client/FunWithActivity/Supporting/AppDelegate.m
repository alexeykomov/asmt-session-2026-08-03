//
//  AppDelegate.m
//  FunWithActivity
//

#import "AppDelegate.h"
#import "FWAGRPCClient.h"
#import "FWAHealthKitService.h"
#import "FWAMeasurementViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

    // Manual, explicit construction — no reflection-heavy DI framework.
    // FWAGRPCClient reads its host from FWAServerConfig (single build-time
    // constant); FWAHealthKitService is nil'd out where HealthKit isn't
    // available so the measurement screen falls back to manual entry only.
    FWAGRPCClient *grpcClient = [[FWAGRPCClient alloc] init];
    FWAHealthKitService *healthKitService = [FWAHealthKitService isHealthDataAvailable]
        ? [[FWAHealthKitService alloc] init]
        : nil;

    FWAMeasurementViewController *rootVC = [[FWAMeasurementViewController alloc]
        initWithGRPCClient:grpcClient healthKitService:healthKitService];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:rootVC];
    nav.navigationBar.prefersLargeTitles = YES;

    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];

    return YES;
}

@end
