/* Copyright 2018 Urban Airship and Contributors */

#import "UABaseTest.h"

#import "UAirship+Internal.h"
#import "UAInAppMessageAdapterProtocol.h"
#import "UAInAppMessageManager+Internal.h"
#import "UASchedule+Internal.h"
#import "UAPreferenceDataStore+Internal.h"
#import "UARemoteDataManager+Internal.h"
#import "UAInAppMessageBannerDisplayContent+Internal.h"
#import "UAPush+Internal.h"
#import "UAInAppMessageAudience.h"
#import "UALocation+Internal.h"
#import "UAActionRunner+Internal.h"
#import "UAInAppMessageAudienceChecks+Internal.h"
#import "UATestDispatcher.h"

@interface UAInAppMessageManagerTest : UABaseTest
@property(nonatomic, strong) UAInAppMessageManager *manager;
@property(nonatomic, strong) id mockDelegate;
@property(nonatomic, strong) id mockAdapter;
@property(nonatomic, strong) id mockAutomationEngine;
@property(nonatomic, strong) UAInAppMessageScheduleInfo *scheduleInfo;
@property (nonatomic, strong) UAPreferenceDataStore *dataStore;
@property (nonatomic, strong) id mockPush;
@property (nonatomic, strong) id mockActionRunner;
@property (nonatomic, strong) UATestDispatcher *testDispatcher;
@end

@implementation UAInAppMessageManagerTest

- (void)setUp {
    [super setUp];

    self.mockDelegate = [self mockForProtocol:@protocol(UAInAppMessagingDelegate)];
    self.mockAdapter = [self mockForProtocol:@protocol(UAInAppMessageAdapterProtocol)];
    self.mockAutomationEngine = [self mockForClass:[UAAutomationEngine class]];
    self.dataStore = [UAPreferenceDataStore preferenceDataStoreWithKeyPrefix:@"UAInAppMessageManagerTest."];
    [self.dataStore removeAll];
    self.mockPush = [self mockForClass:[UAPush class]];
    self.mockActionRunner = [self mockForClass:[UAActionRunner class]];
    self.testDispatcher = [UATestDispatcher testDispatcher];

    self.manager = [UAInAppMessageManager managerWithAutomationEngine:self.mockAutomationEngine
                                                    remoteDataManager:[self mockForClass:[UARemoteDataManager class]]
                                                            dataStore:self.dataStore
                                                                 push:self.mockPush
                                                           dispatcher:self.testDispatcher];
    self.manager.paused = NO;

    self.manager.delegate = self.mockDelegate;

    self.scheduleInfo = [self sampleScheduleInfoWithMissBehavior:UAInAppMessageAudienceMissBehaviorPenalize];

    //Set factory block with banner display type
    UA_WEAKIFY(self)
    [self.manager setFactoryBlock:^id<UAInAppMessageAdapterProtocol> _Nonnull(UAInAppMessage * _Nonnull message) {
        UA_STRONGIFY(self)
        return self.mockAdapter;
    } forDisplayType:UAInAppMessageDisplayTypeBanner];

}

- (void)tearDown {
    [self.mockDelegate stopMocking];
    [self.mockAdapter stopMocking];

    [super tearDown];
}

- (UAInAppMessageScheduleInfo *)sampleScheduleInfoWithMissBehavior:(UAInAppMessageAudienceMissBehaviorType)missBehavior {
    UAInAppMessageScheduleInfo *scheduleInfo = [UAInAppMessageScheduleInfo scheduleInfoWithBuilderBlock:^(UAInAppMessageScheduleInfoBuilder * _Nonnull builder) {
        UAInAppMessage *message = [UAInAppMessage messageWithBuilderBlock:^(UAInAppMessageBuilder * _Nonnull builder) {
            builder.identifier = @"test identifier";
            builder.actions = @{@"cool": @"story"};
            
            builder.displayContent = [UAInAppMessageBannerDisplayContent displayContentWithBuilderBlock:^(UAInAppMessageBannerDisplayContentBuilder *builder) {
                builder.placement = UAInAppMessageBannerPlacementTop;
                builder.buttonLayout = UAInAppMessageButtonLayoutTypeJoined;
                
                UAInAppMessageTextInfo *heading = [UAInAppMessageTextInfo textInfoWithBuilderBlock:^(UAInAppMessageTextInfoBuilder * _Nonnull builder) {
                    builder.text = @"Here is a headline!";
                }];
                builder.heading = heading;
                
                UAInAppMessageTextInfo *buttonTex = [UAInAppMessageTextInfo textInfoWithBuilderBlock:^(UAInAppMessageTextInfoBuilder * _Nonnull builder) {
                    builder.text = @"Dismiss";
                }];
                
                UAInAppMessageButtonInfo *button = [UAInAppMessageButtonInfo buttonInfoWithBuilderBlock:^(UAInAppMessageButtonInfoBuilder * _Nonnull builder) {
                    builder.label = buttonTex;
                    builder.identifier = @"button";
                }];
                
                builder.buttons = @[button];
            }];
            builder.audience = [UAInAppMessageAudience audienceWithBuilderBlock:^(UAInAppMessageAudienceBuilder * _Nonnull builder) {
                builder.locationOptIn = @NO;
                builder.missBehavior = missBehavior;
            }];
        }];
        builder.message = message;
    }];
    return scheduleInfo;
}



- (void)testPrepare {
    XCTestExpectation *prepareCalled = [self expectationWithDescription:@"prepare should be called"];
    [[[self.mockAdapter expect] andDo:^(NSInvocation *invocation) {
        void (^prepareBlock)(UAInAppMessagePrepareResult);
        [invocation getArgument:&prepareBlock atIndex:2];
        prepareBlock(UAInAppMessagePrepareResultSuccess);
        [prepareCalled fulfill];
    }] prepare:OCMOCK_ANY];

    [[self.mockDelegate expect] extendMessage:[OCMArg isKindOfClass:[UAInAppMessage class]]];

    UASchedule *schedule = [UASchedule scheduleWithIdentifier:@"test IAM schedule" info:self.scheduleInfo];

    XCTestExpectation *prepareFinished = [self expectationWithDescription:@"prepare should be finished"];
    [self.manager prepareSchedule:schedule completionHandler:^(UAAutomationSchedulePrepareResult result) {
        XCTAssertEqual(UAAutomationSchedulePrepareResultContinue, result);
        [prepareFinished fulfill];
    }];

    [self waitForTestExpectations];
    
    [self.mockAdapter verify];
    [self.mockDelegate verify];
}

- (void)testPrepareCancel {
    XCTestExpectation *prepareCalled = [self expectationWithDescription:@"prepare should be called"];
    [[[self.mockAdapter expect] andDo:^(NSInvocation *invocation) {
        void (^prepareBlock)(UAInAppMessagePrepareResult);
        [invocation getArgument:&prepareBlock atIndex:2];
        prepareBlock(UAInAppMessagePrepareResultCancel);
        [prepareCalled fulfill];
    }] prepare:OCMOCK_ANY];

    UASchedule *schedule = [UASchedule scheduleWithIdentifier:@"test IAM schedule" info:self.scheduleInfo];

    XCTestExpectation *prepareFinished = [self expectationWithDescription:@"prepare should be finished"];
    [self.manager prepareSchedule:schedule completionHandler:^(UAAutomationSchedulePrepareResult result) {
        XCTAssertEqual(UAAutomationSchedulePrepareResultCancel, result);
        [prepareFinished fulfill];
    }];

    [self waitForTestExpectations];

    [self.mockAdapter verify];
    [self.mockAutomationEngine verify];
}

- (void)testPrepareNoFactory {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    [self.manager setFactoryBlock:nil forDisplayType:UAInAppMessageDisplayTypeBanner];
#pragma clang diagnostic pop

    UASchedule *schedule = [UASchedule scheduleWithIdentifier:@"test IAM schedule" info:self.scheduleInfo];

    XCTestExpectation *prepareFinished = [self expectationWithDescription:@"prepare should be finished"];
    [self.manager prepareSchedule:schedule completionHandler:^(UAAutomationSchedulePrepareResult result) {
        XCTAssertEqual(UAAutomationSchedulePrepareResultPenalize, result);
        [prepareFinished fulfill];
    }];

    [self waitForTestExpectations];

    [self.mockAdapter verify];
}

- (void)testIsScheduleReadyNilAdapter {
    [self.manager setFactoryBlock:^id<UAInAppMessageAdapterProtocol> _Nonnull(UAInAppMessage * _Nonnull message) {
        return nil;
    } forDisplayType:UAInAppMessageDisplayTypeBanner];

    UASchedule *schedule = [UASchedule scheduleWithIdentifier:@"test IAM schedule" info:self.scheduleInfo];

    XCTestExpectation *prepareFinished = [self expectationWithDescription:@"prepare should be finished"];
    [self.manager prepareSchedule:schedule completionHandler:^(UAAutomationSchedulePrepareResult result) {
        XCTAssertEqual(UAAutomationSchedulePrepareResultPenalize, result);
        [prepareFinished fulfill];
    }];

    [self waitForTestExpectations];

    [self.mockAdapter verify];
}

- (void)testPrepareAudienceCheckFailureDefaultMissBehavior {
    UASchedule *testSchedule = [UASchedule scheduleWithIdentifier:@"expected_id" info:self.scheduleInfo];

    // Mock the checks to reject the audience
    id checks = [self mockForClass:[UAInAppMessageAudienceChecks class]];
    [[[checks expect] andReturnValue:@(NO)] checkDisplayAudienceConditions:self.scheduleInfo.message.audience];

    XCTestExpectation *prepareFinished = [self expectationWithDescription:@"prepare should be finished"];
    [self.manager prepareSchedule:testSchedule completionHandler:^(UAAutomationSchedulePrepareResult result) {
        XCTAssertEqual(UAAutomationSchedulePrepareResultPenalize, result);
        [prepareFinished fulfill];
    }];

    [self waitForTestExpectations];

    [checks verify];
}

- (void)testPrepareAudienceCheckFailureMissBehaviorCancel {
    UAInAppMessageScheduleInfo *scheduleInfo = [self sampleScheduleInfoWithMissBehavior:UAInAppMessageAudienceMissBehaviorCancel];
    
    UASchedule *testSchedule = [UASchedule scheduleWithIdentifier:@"expected_id" info:scheduleInfo];
    
    // Mock the checks to reject the audience
    id checks = [self mockForClass:[UAInAppMessageAudienceChecks class]];
    [[[checks expect] andReturnValue:@(NO)] checkDisplayAudienceConditions:scheduleInfo.message.audience];
    
    XCTestExpectation *prepareFinished = [self expectationWithDescription:@"prepare should be finished"];
    [self.manager prepareSchedule:testSchedule completionHandler:^(UAAutomationSchedulePrepareResult result) {
        XCTAssertEqual(UAAutomationSchedulePrepareResultCancel, result);
        [prepareFinished fulfill];
    }];
    
    [self waitForTestExpectations];
    
    [checks verify];
}

- (void)testPrepareAudienceCheckFailureMissBehaviorSkip {
    UAInAppMessageScheduleInfo *scheduleInfo = [self sampleScheduleInfoWithMissBehavior:UAInAppMessageAudienceMissBehaviorSkip];
    
    UASchedule *testSchedule = [UASchedule scheduleWithIdentifier:@"expected_id" info:scheduleInfo];
    
    // Mock the checks to reject the audience
    id checks = [self mockForClass:[UAInAppMessageAudienceChecks class]];
    [[[checks expect] andReturnValue:@(NO)] checkDisplayAudienceConditions:scheduleInfo.message.audience];
    
    XCTestExpectation *prepareFinished = [self expectationWithDescription:@"prepare should be finished"];
    [self.manager prepareSchedule:testSchedule completionHandler:^(UAAutomationSchedulePrepareResult result) {
        XCTAssertEqual(UAAutomationSchedulePrepareResultSkip, result);
        [prepareFinished fulfill];
    }];
    
    [self waitForTestExpectations];
    
    [checks verify];
}

- (void)testPrepareAudienceCheckFailureMissBehaviorPenalize {
    UAInAppMessageScheduleInfo *scheduleInfo = [self sampleScheduleInfoWithMissBehavior:UAInAppMessageAudienceMissBehaviorPenalize];
    
    UASchedule *testSchedule = [UASchedule scheduleWithIdentifier:@"expected_id" info:scheduleInfo];
    
    // Mock the checks to reject the audience
    id checks = [self mockForClass:[UAInAppMessageAudienceChecks class]];
    [[[checks expect] andReturnValue:@(NO)] checkDisplayAudienceConditions:scheduleInfo.message.audience];
    
    XCTestExpectation *prepareFinished = [self expectationWithDescription:@"prepare should be finished"];
    [self.manager prepareSchedule:testSchedule completionHandler:^(UAAutomationSchedulePrepareResult result) {
        XCTAssertEqual(UAAutomationSchedulePrepareResultPenalize, result);
        [prepareFinished fulfill];
    }];
    
    [self waitForTestExpectations];
    
    [checks verify];
}

- (void)testExecuteSchedule {
    UASchedule *testSchedule = [UASchedule scheduleWithIdentifier:@"expected_id" info:self.scheduleInfo];

    // Prepare
    [[[self.mockAdapter expect] andDo:^(NSInvocation *invocation) {
        void (^prepareBlock)(UAInAppMessagePrepareResult);
        [invocation getArgument:&prepareBlock atIndex:2];
        prepareBlock(UAInAppMessagePrepareResultSuccess);
    }] prepare:OCMOCK_ANY];

    XCTestExpectation *prepareFinished = [self expectationWithDescription:@"prepare should be finished"];
    [self.manager prepareSchedule:testSchedule completionHandler:^(UAAutomationSchedulePrepareResult result) {
        XCTAssertEqual(UAAutomationSchedulePrepareResultContinue, result);
        [prepareFinished fulfill];
    }];

    [self waitForTestExpectations];

    // isReady
    [[[self.mockAdapter stub] andReturnValue:@(YES)] isReadyToDisplay];
    XCTAssertTrue([self.manager isScheduleReadyToExecute:testSchedule]);

    // Display
    XCTestExpectation *displayBlockCalled = [self expectationWithDescription:@"display block should be called"];
    [[[self.mockAdapter expect] andDo:^(NSInvocation *invocation) {
        void (^displayBlock)(UAInAppMessageResolution *);
        [invocation getArgument:&displayBlock atIndex:2];
        displayBlock([UAInAppMessageResolution userDismissedResolution]);
        [displayBlockCalled fulfill];
    }] display:OCMOCK_ANY];

    [[self.mockActionRunner expect] runActionsWithActionValues:self.scheduleInfo.message.actions
                                                     situation:UASituationManualInvocation
                                                      metadata:nil
                                             completionHandler:OCMOCK_ANY];

    [[self.mockDelegate expect] messageWillBeDisplayed:self.scheduleInfo.message scheduleID:testSchedule.identifier];
    [[self.mockDelegate expect] messageFinishedDisplaying:self.scheduleInfo.message scheduleID:testSchedule.identifier resolution:OCMOCK_ANY];

    XCTestExpectation *executeFinished = [self expectationWithDescription:@"execute finished"];
    [self.manager executeSchedule:testSchedule completionHandler:^{
        [executeFinished fulfill];
    }];

    [self waitForTestExpectations];

    [self.mockAdapter verify];
    [self.mockDelegate verify];
    [self.mockActionRunner verify];
}

- (void)testPauseDisplay {
    UASchedule *testSchedule = [UASchedule scheduleWithIdentifier:@"expected_id" info:self.scheduleInfo];

    // Prepare
    [[[self.mockAdapter expect] andDo:^(NSInvocation *invocation) {
        void (^prepareBlock)(UAInAppMessagePrepareResult);
        [invocation getArgument:&prepareBlock atIndex:2];
        prepareBlock(UAInAppMessagePrepareResultSuccess);
    }] prepare:OCMOCK_ANY];

    XCTestExpectation *prepareFinished = [self expectationWithDescription:@"prepare should be finished"];
    [self.manager prepareSchedule:testSchedule completionHandler:^(UAAutomationSchedulePrepareResult result) {
        XCTAssertEqual(UAAutomationSchedulePrepareResultContinue, result);
        [prepareFinished fulfill];
    }];

    [self waitForTestExpectations];

    // isReady
    [[[self.mockAdapter stub] andReturnValue:@(YES)] isReadyToDisplay];
    XCTAssertTrue([self.manager isScheduleReadyToExecute:testSchedule]);

    // Should display when paused == NO
    XCTAssertTrue([self.manager isScheduleReadyToExecute:testSchedule]);

    // Pause the manager
    self.manager.paused = YES;

    // Should not display when paused
    XCTAssertFalse([self.manager isScheduleReadyToExecute:testSchedule]);
}

- (void)testCancelMessage {
    [[self.mockAutomationEngine expect] cancelSchedulesWithGroup:self.scheduleInfo.message.identifier];

    [self.manager cancelMessagesWithID:self.scheduleInfo.message.identifier];

    [self.mockAutomationEngine verify];
}

- (void)testCancelSchedule {
    UASchedule *testSchedule = [UASchedule scheduleWithIdentifier:@"expected_id" info:self.scheduleInfo];

    [[self.mockAutomationEngine expect] cancelScheduleWithID:testSchedule.identifier];

    [self.manager cancelScheduleWithID:testSchedule.identifier];

    [self.mockAutomationEngine verify];
}

- (void)testComponentEnabled {
    XCTAssertTrue(self.manager.componentEnabled);

    // test disable
    [[self.mockAutomationEngine expect] pause];
    self.manager.componentEnabled = NO;

    // verify
    XCTAssertFalse(self.manager.componentEnabled);
    [self.mockAutomationEngine verify];

    // test enable
    [[self.mockAutomationEngine expect] resume];
    self.manager.componentEnabled = YES;

    // verify
    XCTAssertTrue(self.manager.componentEnabled);
    [self.mockAutomationEngine verify];
}

- (void)testEnable {
    XCTAssertTrue(self.manager.isEnabled);

    // test disable
    [[self.mockAutomationEngine expect] pause];
    self.manager.enabled = NO;

    // verify
    XCTAssertFalse(self.manager.isEnabled);
    [self.mockAutomationEngine verify];

    // test enable
    [[self.mockAutomationEngine expect] resume];
    self.manager.enabled = YES;

    // verify
    XCTAssertTrue(self.manager.isEnabled);
    [self.mockAutomationEngine verify];
}

- (void)testScheduleMessagesWithScheduleInfo {
    // setup
    UAInAppMessageScheduleInfo *anotherScheduleInfo = [UAInAppMessageScheduleInfo scheduleInfoWithBuilderBlock:^(UAInAppMessageScheduleInfoBuilder * _Nonnull builder) {
        UAInAppMessage *message = [UAInAppMessage messageWithBuilderBlock:^(UAInAppMessageBuilder * _Nonnull builder) {
            builder.identifier = @"another test identifier";
        }];
        
        builder.message = message;
    }];
    NSArray<UAInAppMessageScheduleInfo *> *submittedScheduleInfos = @[self.scheduleInfo,anotherScheduleInfo];
    
    // expectations
    [[[self.mockAutomationEngine expect] andDo:^(NSInvocation *invocation) {
        void *arg;
        [invocation getArgument:&arg atIndex:3];
        void (^completionHandler)(NSArray *) = (__bridge void (^)(NSArray *))arg;
        
        if (completionHandler) {
            completionHandler(@[]);
        }
    }] scheduleMultiple:[OCMArg checkWithBlock:^BOOL(NSArray<UAInAppMessageScheduleInfo *> *scheduleInfos) {
        return [scheduleInfos isEqualToArray:submittedScheduleInfos];
    }] completionHandler:OCMOCK_ANY];
    
    // test
    __block BOOL completionHandlerCalled = NO;
    [self.manager scheduleMessagesWithScheduleInfo:submittedScheduleInfos completionHandler:^(NSArray<UASchedule *> *schedules) {
        completionHandlerCalled = YES;

    }];
    
    // verify
    XCTAssertTrue(completionHandlerCalled);
    [self.mockAutomationEngine verify];
}

- (void)testDisplayLock {
    self.manager.displayInterval = 10000;

    UASchedule *testSchedule = [UASchedule scheduleWithIdentifier:@"expected_id" info:self.scheduleInfo];

    [[[self.mockAdapter stub] andDo:^(NSInvocation *invocation) {
        void (^prepareBlock)(UAInAppMessagePrepareResult);
        [invocation getArgument:&prepareBlock atIndex:2];
        prepareBlock(UAInAppMessagePrepareResultSuccess);
    }] prepare:OCMOCK_ANY];

    [[[self.mockAdapter stub] andReturnValue:@(YES)] isReadyToDisplay];

    // Prepare
    XCTestExpectation *prepareFinished = [self expectationWithDescription:@"prepare should be finished"];
    [self.manager prepareSchedule:testSchedule completionHandler:^(UAAutomationSchedulePrepareResult result) {
        XCTAssertEqual(UAAutomationSchedulePrepareResultContinue, result);
        [prepareFinished fulfill];
    }];

    [self waitForTestExpectations];

    // isReady
    XCTAssertTrue([self.manager isScheduleReadyToExecute:testSchedule]);

    // Display
    XCTestExpectation *displayBlockCalled = [self expectationWithDescription:@"display block should be called"];
    [[[self.mockAdapter expect] andDo:^(NSInvocation *invocation) {
        void (^displayBlock)(UAInAppMessageResolution *);
        [invocation getArgument:&displayBlock atIndex:2];
        displayBlock([UAInAppMessageResolution userDismissedResolution]);
        [displayBlockCalled fulfill];
    }] display:OCMOCK_ANY];

    XCTestExpectation *executeFinished = [self expectationWithDescription:@"execute finished"];
    [self.manager executeSchedule:testSchedule completionHandler:^{
        [executeFinished fulfill];
    }];

    [self waitForTestExpectations];

    // Prepare again
    prepareFinished = [self expectationWithDescription:@"prepare should be finished"];
    [self.manager prepareSchedule:testSchedule completionHandler:^(UAAutomationSchedulePrepareResult result) {
        XCTAssertEqual(UAAutomationSchedulePrepareResultContinue, result);
        [prepareFinished fulfill];
    }];

    [self waitForTestExpectations];

    // False - display is locked
    XCTAssertFalse([self.manager isScheduleReadyToExecute:testSchedule]);

    // Advance dispatcher
    [self.testDispatcher advanceTime:9999];

    // False - should still be locked
    XCTAssertFalse([self.manager isScheduleReadyToExecute:testSchedule]);

    // Advance dispatcher
    [self.testDispatcher advanceTime:1];

    // True - display is unlocked
    XCTAssertTrue([self.manager isScheduleReadyToExecute:testSchedule]);

    [self.mockAutomationEngine verify];
}


@end
