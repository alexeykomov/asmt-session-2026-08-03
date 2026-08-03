//
//  FWAMeasurementViewController.h
//  FunWithActivity
//
//  Measurement entry screen: height (cm), weight (kg), and an explicitly
//  optional birth date. Prefills from HealthKit when available and
//  authorized; always allows manual entry as a fallback.
//

#import <UIKit/UIKit.h>

@class FWAGRPCClient;
@class FWAHealthKitService;

NS_ASSUME_NONNULL_BEGIN

@interface FWAMeasurementViewController : UIViewController

/// Explicit construction — dependencies are passed in, never resolved via
/// a reflection-heavy DI container. healthKitService is nil on devices/
/// simulators without HealthKit; the screen still works, minus prefill.
- (instancetype)initWithGRPCClient:(FWAGRPCClient *)grpcClient
                    healthKitService:(nullable FWAHealthKitService *)healthKitService NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil
                          bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
