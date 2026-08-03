//
//  FWAAppState.m
//  FunWithActivityCore
//

#import "FWAAppState.h"
#import "Recommendations.pbobjc.h"

NSString *const FWAAppStateDidUpdateStatusesNotification = @"FWAAppStateDidUpdateStatusesNotification";

NSString *const FWAFaultModeError = @"error";
NSString *const FWAFaultModeTimeout = @"timeout";
NSString *const FWAFaultModeMalformed = @"malformed";

static const NSUInteger kFWAProviderCount = 2;

@interface FWAAppState ()

@property (nonatomic, strong, readwrite) NSArray<NSString *> *providerNames;
@property (nonatomic, strong, readwrite, nullable) NSArray<ProviderStatus *> *lastStatuses;
@property (nonatomic, assign, readwrite) BOOL isDirty;

@property (nonatomic, strong) NSMutableArray<NSNumber *> *faultEnabledFlags;
@property (nonatomic, strong) NSMutableArray<NSString *> *faultModes;

@end

@implementation FWAAppState

- (instancetype)init {
    self = [super init];
    if (self) {
        // Same defaults FWAMeasurementViewController used to seed its form
        // with, preserved here so a fresh launch still demos cleanly: a
        // non-nil birth date is required for the "clear it and watch the
        // banner change" beat to have something to clear.
        _heightCm = 175;
        _weightKg = 70;
        _birthDate = [self defaultBirthDate];

        _providerNames = @[@"service1", @"service2"];
        _faultEnabledFlags = [@[@NO, @NO] mutableCopy];
        _faultModes = [@[FWAFaultModeError, FWAFaultModeError] mutableCopy];

        _isDirty = NO;
        _lastStatuses = nil;
    }
    return self;
}

- (NSDate *)defaultBirthDate {
    NSDateComponents *components = [[NSDateComponents alloc] init];
    components.year = 1990;
    components.month = 1;
    components.day = 1;
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    return [calendar dateFromComponents:components] ?: [NSDate date];
}

#pragma mark - Measurements

- (void)setHeightCm:(double)heightCm {
    if (_heightCm == heightCm) return;
    _heightCm = heightCm;
    self.isDirty = YES;
}

- (void)setWeightKg:(double)weightKg {
    if (_weightKg == weightKg) return;
    _weightKg = weightKg;
    self.isDirty = YES;
}

- (void)setBirthDate:(nullable NSDate *)birthDate {
    if (_birthDate == birthDate || [_birthDate isEqualToDate:birthDate]) return;
    _birthDate = birthDate;
    self.isDirty = YES;
}

#pragma mark - Developer fault injection

- (BOOL)faultEnabledAtIndex:(NSUInteger)index {
    if (index >= self.faultEnabledFlags.count) return NO;
    return self.faultEnabledFlags[index].boolValue;
}

- (void)setFaultEnabled:(BOOL)enabled atIndex:(NSUInteger)index {
    if (index >= self.faultEnabledFlags.count) return;
    if (self.faultEnabledFlags[index].boolValue == enabled) return;
    self.faultEnabledFlags[index] = @(enabled);
    self.isDirty = YES;
}

- (NSString *)faultModeAtIndex:(NSUInteger)index {
    if (index >= self.faultModes.count) return FWAFaultModeError;
    return self.faultModes[index];
}

- (void)setFaultMode:(NSString *)mode atIndex:(NSUInteger)index {
    if (index >= self.faultModes.count) return;
    if ([self.faultModes[index] isEqualToString:mode]) return;
    self.faultModes[index] = [mode copy];
    self.isDirty = YES;
}

#pragma mark - Dirty flag

- (void)clearDirty {
    self.isDirty = NO;
}

#pragma mark - Most recent fetch result

- (void)recordResponse:(GetRecommendationsResponse *)response {
    NSArray<ProviderStatus *> *statuses = [response.statusesArray copy] ?: @[];
    self.lastStatuses = statuses;

    if (statuses.count == kFWAProviderCount) {
        NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:kFWAProviderCount];
        for (ProviderStatus *status in statuses) {
            [names addObject:status.name ?: @"unknown"];
        }
        self.providerNames = [names copy];
    }
    // A response with a different provider count than expected (should not
    // happen in this app's configuration) leaves providerNames as-is rather
    // than guessing at a remap.

    [[NSNotificationCenter defaultCenter] postNotificationName:FWAAppStateDidUpdateStatusesNotification
                                                          object:self];
}

- (nullable NSDictionary<NSString *, NSString *> *)faultsForRequest {
    NSMutableDictionary<NSString *, NSString *> *faults = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < kFWAProviderCount && i < self.providerNames.count; i++) {
        if ([self faultEnabledAtIndex:i]) {
            faults[self.providerNames[i]] = [self faultModeAtIndex:i];
        }
    }
    return faults.count > 0 ? [faults copy] : nil;
}

@end
