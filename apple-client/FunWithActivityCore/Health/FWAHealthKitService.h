//
//  FWAHealthKitService.h
//  FunWithActivityCore
//
//  Reads height, weight and date of birth from HealthKit to prefill the
//  measurement form. Manual entry always remains available — this is a
//  convenience prefill, never a hard requirement. Callers MUST treat
//  denied/unavailable/absent-data as a normal, expected outcome, not an
//  error to surface to the user.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Result of a HealthKit read. Any field can be "not available" — height/
/// weight of 0 means no sample was found (or permission was denied), and a
/// nil birthDate means the same. The caller falls back to blank manual-entry
/// fields for whichever values are unavailable.
@interface FWAHealthKitMeasurements : NSObject

@property (nonatomic, assign, readonly) double heightCm;   // 0 = unavailable
@property (nonatomic, assign, readonly) double weightKg;   // 0 = unavailable
@property (nonatomic, strong, readonly, nullable) NSDate *birthDate;

- (instancetype)initWithHeightCm:(double)heightCm
                          weightKg:(double)weightKg
                        birthDate:(nullable NSDate *)birthDate NS_DESIGNATED_INITIALIZER;

@end

typedef void (^FWAHealthKitAuthorizationBlock)(BOOL granted, NSError *_Nullable error);
typedef void (^FWAHealthKitReadBlock)(FWAHealthKitMeasurements *measurements);

@interface FWAHealthKitService : NSObject

/// Whether this device supports HealthKit at all (false on some
/// simulators/devices — always check before requesting authorization).
+ (BOOL)isHealthDataAvailable;

/// Requests read authorization for height, body mass and date of birth.
/// `granted` reflects whether the request completed, NOT whether the user
/// actually allowed every type — HealthKit deliberately does not reveal
/// per-type grant/deny status for privacy reasons, so a subsequent read
/// that comes back empty is the only signal of a partial/full deny.
- (void)requestAuthorizationWithCompletion:(FWAHealthKitAuthorizationBlock)completion;

/// Best-effort read of the most recent height/weight samples and date of
/// birth. Never fails — any value HealthKit doesn't have (or wasn't
/// authorized for) comes back as "unavailable" per FWAHealthKitMeasurements,
/// letting the caller silently fall back to manual entry field-by-field.
- (void)fetchMeasurementsWithCompletion:(FWAHealthKitReadBlock)completion;

@end

NS_ASSUME_NONNULL_END
