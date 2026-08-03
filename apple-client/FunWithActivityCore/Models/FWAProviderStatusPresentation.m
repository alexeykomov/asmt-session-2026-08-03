//
//  FWAProviderStatusPresentation.m
//  FunWithActivityCore
//

#import "FWAProviderStatusPresentation.h"
#import "Recommendations.pbobjc.h"

@interface FWAProviderStatusPresentation ()
- (instancetype)initWithProviderName:(NSString *)providerName
                             severity:(FWAProviderStatusSeverity)severity
                              message:(NSString *)message NS_DESIGNATED_INITIALIZER;
@end

@implementation FWAProviderStatusPresentation

- (instancetype)initWithProviderName:(NSString *)providerName
                             severity:(FWAProviderStatusSeverity)severity
                              message:(NSString *)message {
    self = [super init];
    if (self) {
        _providerName = [providerName copy];
        _severity = severity;
        _message = [message copy];
    }
    return self;
}

+ (NSArray<FWAProviderStatusPresentation *> *)presentationsForStatuses:(NSArray<ProviderStatus *> *)statuses {
    NSMutableArray<FWAProviderStatusPresentation *> *result = [NSMutableArray array];

    for (ProviderStatus *status in statuses) {
        if (status.ok) {
            continue;
        }

        // Branch on `skipped` BEFORE `error` — see header doc.
        if (status.skipped) {
            NSString *reason = status.error.length > 0 ? status.error : @"input not supplied";
            NSString *message = [NSString stringWithFormat:@"%@ skipped — %@", status.name, reason];
            [result addObject:[[self alloc] initWithProviderName:status.name
                                                          severity:FWAProviderStatusSeverityInfo
                                                           message:message]];
        } else {
            NSString *message = [NSString stringWithFormat:@"%@ unavailable — showing partial results", status.name];
            [result addObject:[[self alloc] initWithProviderName:status.name
                                                          severity:FWAProviderStatusSeverityDegraded
                                                           message:message]];
        }
    }

    return result;
}

+ (instancetype)presentationWithProviderName:(NSString *)providerName
                                     severity:(FWAProviderStatusSeverity)severity
                                      message:(NSString *)message {
    return [[self alloc] initWithProviderName:providerName severity:severity message:message];
}

@end
