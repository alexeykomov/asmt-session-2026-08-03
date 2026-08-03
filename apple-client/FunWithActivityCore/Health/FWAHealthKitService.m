//
//  FWAHealthKitService.m
//  FunWithActivityCore
//

#import "FWAHealthKitService.h"
#import <HealthKit/HealthKit.h>
#import <os/log.h>

static os_log_t FWAHealthLog(void) {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("com.funwithactivity.ios", "healthkit");
    });
    return log;
}

@implementation FWAHealthKitMeasurements

- (instancetype)initWithHeightCm:(double)heightCm
                          weightKg:(double)weightKg
                        birthDate:(nullable NSDate *)birthDate {
    self = [super init];
    if (self) {
        _heightCm = heightCm;
        _weightKg = weightKg;
        _birthDate = birthDate;
    }
    return self;
}

@end

@interface FWAHealthKitService ()
@property (nonatomic, strong) HKHealthStore *store;
@end

@implementation FWAHealthKitService

- (instancetype)init {
    self = [super init];
    if (self) {
        if ([HKHealthStore isHealthDataAvailable]) {
            _store = [[HKHealthStore alloc] init];
        }
    }
    return self;
}

+ (BOOL)isHealthDataAvailable {
    return [HKHealthStore isHealthDataAvailable];
}

- (NSSet<HKObjectType *> *)readTypes {
    NSMutableSet<HKObjectType *> *types = [NSMutableSet set];
    HKQuantityType *height = [HKObjectType quantityTypeForIdentifier:HKQuantityTypeIdentifierHeight];
    HKQuantityType *bodyMass = [HKObjectType quantityTypeForIdentifier:HKQuantityTypeIdentifierBodyMass];
    HKCharacteristicType *dob = [HKObjectType characteristicTypeForIdentifier:HKCharacteristicTypeIdentifierDateOfBirth];
    if (height) [types addObject:height];
    if (bodyMass) [types addObject:bodyMass];
    if (dob) [types addObject:dob];
    return types;
}

- (void)requestAuthorizationWithCompletion:(FWAHealthKitAuthorizationBlock)completion {
    if (!self.store) {
        os_log(FWAHealthLog(), "requestAuthorization — HealthKit unavailable on this device");
        if (completion) {
            completion(NO, nil);
        }
        return;
    }

    [self.store requestAuthorizationToShareTypes:nil
                                        readTypes:[self readTypes]
                                       completion:^(BOOL success, NSError * _Nullable error) {
        os_log(FWAHealthLog(), "requestAuthorization completed — success=%d error=%{public}@", success, error);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(success, error);
            }
        });
    }];
}

- (void)fetchMeasurementsWithCompletion:(FWAHealthKitReadBlock)completion {
    if (!self.store) {
        if (completion) {
            completion([[FWAHealthKitMeasurements alloc] initWithHeightCm:0 weightKg:0 birthDate:nil]);
        }
        return;
    }

    __block double heightCm = 0;
    __block double weightKg = 0;
    NSDate *birthDate = [self readBirthDate];

    dispatch_group_t group = dispatch_group_create();

    dispatch_group_enter(group);
    [self mostRecentQuantitySampleForIdentifier:HKQuantityTypeIdentifierHeight
                                            unit:[HKUnit unitFromString:@"cm"]
                                      completion:^(double value) {
        heightCm = value;
        dispatch_group_leave(group);
    }];

    dispatch_group_enter(group);
    [self mostRecentQuantitySampleForIdentifier:HKQuantityTypeIdentifierBodyMass
                                            unit:[HKUnit unitFromString:@"kg"]
                                      completion:^(double value) {
        weightKg = value;
        dispatch_group_leave(group);
    }];

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        os_log(FWAHealthLog(), "fetchMeasurements — heightCm=%.1f weightKg=%.1f hasBirthDate=%d",
               heightCm, weightKg, birthDate != nil);
        if (completion) {
            completion([[FWAHealthKitMeasurements alloc] initWithHeightCm:heightCm
                                                                    weightKg:weightKg
                                                                  birthDate:birthDate]);
        }
    });
}

#pragma mark - Private

- (nullable NSDate *)readBirthDate {
    NSError *error = nil;
    NSDateComponents *components = [self.store dateOfBirthComponentsWithError:&error];
    if (error || !components) {
        // Not authorized, not set by the user, or unavailable — all
        // treated identically as "no prefill"; the manual date picker
        // remains the fallback.
        return nil;
    }
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    return [calendar dateFromComponents:components];
}

- (void)mostRecentQuantitySampleForIdentifier:(HKQuantityTypeIdentifier)identifier
                                          unit:(HKUnit *)unit
                                    completion:(void (^)(double value))completion {
    HKQuantityType *type = [HKObjectType quantityTypeForIdentifier:identifier];
    if (!type) {
        completion(0);
        return;
    }

    NSSortDescriptor *sort = [NSSortDescriptor sortDescriptorWithKey:HKSampleSortIdentifierEndDate ascending:NO];
    HKSampleQuery *query = [[HKSampleQuery alloc] initWithSampleType:type
                                                             predicate:nil
                                                                 limit:1
                                                       sortDescriptors:@[sort]
                                                        resultsHandler:^(HKSampleQuery *_Nonnull query,
                                                                          NSArray<__kindof HKSample *> *_Nullable results,
                                                                          NSError *_Nullable error) {
        HKQuantitySample *sample = results.firstObject;
        double value = (error || !sample) ? 0 : [sample.quantity doubleValueForUnit:unit];
        completion(value);
    }];
    [self.store executeQuery:query];
}

@end
