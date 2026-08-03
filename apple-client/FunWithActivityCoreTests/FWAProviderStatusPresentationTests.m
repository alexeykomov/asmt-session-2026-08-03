//
//  FWAProviderStatusPresentationTests.m
//  FunWithActivityCoreTests
//
//  FWAProviderStatusPresentation is required to branch on `skipped` BEFORE
//  `error` (see its header doc) — a skipped ProviderStatus also carries text
//  in the `error` field, so checking `error` first would render deliberate
//  GDPR data-minimisation ("birth date not supplied") as a provider outage.
//  That inversion has already caused three defects on this project, so this
//  is exercised explicitly rather than trusted to code review alone.
//

#import <XCTest/XCTest.h>
#import "FWAProviderStatusPresentation.h"
#import "Recommendations.pbobjc.h"

@interface FWAProviderStatusPresentationTests : XCTestCase
@end

@implementation FWAProviderStatusPresentationTests

- (ProviderStatus *)statusNamed:(NSString *)name
                              ok:(BOOL)ok
                         skipped:(BOOL)skipped
                           error:(NSString *)error {
    ProviderStatus *status = [[ProviderStatus alloc] init];
    status.name = name;
    status.ok = ok;
    status.skipped = skipped;
    status.error = error;
    return status;
}

/// ok == true statuses need no banner at all.
- (void)testOkStatusProducesNoPresentation {
    ProviderStatus *status = [self statusNamed:@"service1-stub" ok:YES skipped:NO error:@""];

    NSArray<FWAProviderStatusPresentation *> *presentations =
        [FWAProviderStatusPresentation presentationsForStatuses:@[ status ]];

    XCTAssertEqual(presentations.count, 0u);
}

/// The case that matters most: ok == false, skipped == true, and `error`
/// is ALSO populated (the skipped reason text lives there on the wire).
/// This MUST render as informational (Info), never as Degraded — that is
/// the exact inversion that has caused three prior defects. If the
/// implementation's if/else branch order were reversed to check `error`
/// before `skipped`, this assertion would fail because `error.length > 0`
/// would route it into the Degraded ("unavailable") branch instead.
- (void)testSkippedStatusWithErrorTextRendersAsInfoNotDegraded {
    ProviderStatus *status = [self statusNamed:@"service2-stub"
                                              ok:NO
                                         skipped:YES
                                           error:@"required measurements not supplied"];

    NSArray<FWAProviderStatusPresentation *> *presentations =
        [FWAProviderStatusPresentation presentationsForStatuses:@[ status ]];

    XCTAssertEqual(presentations.count, 1u);
    FWAProviderStatusPresentation *presentation = presentations.firstObject;
    XCTAssertEqual(presentation.severity, FWAProviderStatusSeverityInfo);
    XCTAssertTrue([presentation.message containsString:@"skipped"]);
}

/// A genuine outage: ok == false, skipped == false. Must render as
/// Degraded.
- (void)testGenuineFailureRendersAsDegraded {
    ProviderStatus *status = [self statusNamed:@"service1-stub"
                                              ok:NO
                                         skipped:NO
                                           error:@"upstream timeout"];

    NSArray<FWAProviderStatusPresentation *> *presentations =
        [FWAProviderStatusPresentation presentationsForStatuses:@[ status ]];

    XCTAssertEqual(presentations.count, 1u);
    FWAProviderStatusPresentation *presentation = presentations.firstObject;
    XCTAssertEqual(presentation.severity, FWAProviderStatusSeverityDegraded);
    XCTAssertTrue([presentation.message containsString:@"unavailable"]);
}

@end
