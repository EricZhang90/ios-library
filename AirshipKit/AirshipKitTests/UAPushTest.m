
/* Copyright Airship and Contributors */

#import "UABaseTest.h"
#import "UAPush+Internal.h"
#import "UAChannel+Internal.h"
#import "UAirship.h"
#import "UAirship+Internal.h"
#import "UAActionRunner+Internal.h"
#import "UAActionRegistry+Internal.h"
#import "UAUtils+Internal.h"
#import "UAUser.h"
#import "UAChannelRegistrationPayload+Internal.h"
#import "UAChannelRegistrar+Internal.h"
#import "UAEvent.h"
#import "UAInteractiveNotificationEvent+Internal.h"
#import "UANotificationCategories+Internal.h"
#import "UANotificationAction.h"
#import "UANotificationCategory.h"
#import "UAPreferenceDataStore+Internal.h"
#import "UARuntimeConfig.h"
#import "UATagGroupsRegistrar+Internal.h"
#import "UANotificationCategory.h"
#import "UAPushReceivedEvent+Internal.h"
#import "UATestDispatcher.h"
#import "UAChannelRegistrar+Internal.h"

@interface UAPushTest : UABaseTest
@property (nonatomic, strong) id mockApplication;
@property (nonatomic, strong) id mockChannel;
@property (nonatomic, strong) id mockAppStateTracker;
@property (nonatomic, strong) id mockAirship;
@property (nonatomic, strong) id mockPushDelegate;
@property (nonatomic, strong) id mockRegistrationDelegate;
@property (nonatomic, strong) id mockActionRunner;
@property (nonatomic, strong) id mockUAUtils;
@property (nonatomic, strong) id mockUAUser;
@property (nonatomic, strong) id mockDefaultNotificationCategories;
@property (nonatomic, strong) id mockTagGroupsRegistrar;
@property (nonatomic, strong) id mockUNNotification;
@property (nonatomic, strong) id mockPushRegistration;
@property (nonatomic, strong) id mockUserInfo;

@property (nonatomic, strong) UAPush *push;
@property (nonatomic, strong) NSNotificationCenter *notificationCenter;

@property (nonatomic, strong) NSDictionary *notification;

@property (nonatomic, strong) NSData *validAPNSDeviceToken;

@property (nonatomic, assign) UAAuthorizationStatus authorizationStatus;
@property (nonatomic, assign) UAAuthorizedNotificationSettings authorizedNotificationSettings;

@end

@implementation UAPushTest

NSString *validDeviceToken = @"0123456789abcdef0123456789abcdef";

- (void)setUp {
    [super setUp];

    self.validAPNSDeviceToken = [validDeviceToken dataUsingEncoding:NSASCIIStringEncoding];
    assert([self.validAPNSDeviceToken length] <= 32);

    self.authorizationStatus = UAAuthorizationStatusAuthorized;
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsNone;

    self.mockPushRegistration = [self mockForClass:[UAAPNSRegistration class]];
    typedef void (^GetAuthorizedSettingsCompletionBlock)(UAAuthorizedNotificationSettings, UAAuthorizationStatus);
    [[[self.mockPushRegistration stub] andDo:^(NSInvocation *invocation) {
        void *arg;
        [invocation getArgument:&arg atIndex:2];
        GetAuthorizedSettingsCompletionBlock completionHandler = (__bridge GetAuthorizedSettingsCompletionBlock)arg;
        completionHandler(self.authorizedNotificationSettings,self.authorizationStatus);
    }] getAuthorizedSettingsWithCompletionHandler:OCMOCK_ANY];

    self.mockTagGroupsRegistrar = [self mockForClass:[UATagGroupsRegistrar class]];

    self.notificationCenter = [[NSNotificationCenter alloc] init];

    self.notification = @{
        @"aps": @{
                @"alert": @"sample alert!",
                @"badge": @2,
                @"sound": @"cat",
                @"category": @"notificationCategory"
        },
        @"com.urbanairship.interactive_actions": @{
                @"backgroundIdentifier": @{
                        @"backgroundAction": @"backgroundActionValue"
                },
                @"foregroundIdentifier": @{
                        @"foregroundAction": @"foregroundActionValue",
                        @"otherForegroundAction": @"otherForegroundActionValue"

                },
        },
        @"someActionKey": @"someActionValue",
    };

    // Mock the nested apple types with unavailable init methods
    self.mockUNNotification = [self mockForClass:[UNNotification class]];

    //Mock the notification request
    id mockUNNotificationRequest = [self mockForClass:[UNNotificationRequest class]];
    [[[self.mockUNNotification stub] andReturn:mockUNNotificationRequest] request];

    //Mock the notification content
    id mockUNNotificationContent = [self mockForClass:[UNNotificationContent class]];
    [[[mockUNNotificationRequest stub] andReturn:mockUNNotificationContent] content];

    //Mock the notification userInfo
    self.mockUserInfo = [self mockForClass:[NSDictionary class]];
    [[[mockUNNotificationContent stub] andReturn:self.mockUserInfo] userInfo];

    // Set up a mocked application
    self.mockApplication = [self mockForClass:[UIApplication class]];

    self.mockAirship = [self mockForClass:[UAirship class]];

    [UAirship setSharedAirship:self.mockAirship];

    self.mockPushDelegate = [self mockForProtocol:@protocol(UAPushNotificationDelegate)];
    self.mockRegistrationDelegate = [self mockForProtocol:@protocol(UARegistrationDelegate)];
    self.mockActionRunner = [self strictMockForClass:[UAActionRunner class]];

    self.mockUAUser = [self mockForClass:[UAUser class]];
    [[[self.mockAirship stub] andReturn:self.mockUAUser] inboxUser];

    self.mockDefaultNotificationCategories = [self mockForClass:[UANotificationCategories class]];

    self.mockChannel = [self mockForClass:[UAChannel class]];

    self.mockAppStateTracker = [self mockForProtocol:@protocol(UAAppStateTracker)];

    self.push = [UAPush pushWithConfig:self.config
                             dataStore:self.dataStore
                               channel:self.mockChannel
                       appStateTracker:self.mockAppStateTracker
                    notificationCenter:self.notificationCenter
                      pushRegistration:self.mockPushRegistration
                           application:self.mockApplication
                            dispatcher:[UATestDispatcher testDispatcher]];

    self.push.registrationDelegate = self.mockRegistrationDelegate;
    self.push.pushRegistration = self.mockPushRegistration;
    self.push.pushNotificationDelegate = self.mockPushDelegate;
}

- (void)tearDown {
    self.push.pushNotificationDelegate = nil;
    self.push.registrationDelegate = nil;
    self.push = nil;

    [self.dataStore removeAll];

    [super tearDown];
}

- (void)testSetDeviceToken {
    self.push.deviceToken = nil;

    self.push.deviceToken = @"invalid characters";

    XCTAssertNil(self.push.deviceToken, @"setDeviceToken should ignore device tokens with invalid characters.");

    self.push.deviceToken = validDeviceToken;
    XCTAssertEqualObjects(validDeviceToken, self.push.deviceToken, @"setDeviceToken should set tokens with valid characters");

    self.push.deviceToken = nil;
    XCTAssertNil(self.push.deviceToken,
                 @"setDeviceToken should allow a nil device token.");

    self.push.deviceToken = @"";
    XCTAssertEqualObjects(@"", self.push.deviceToken,
                          @"setDeviceToken should do nothing to an empty string");
}

- (void)testAutoBadgeEnabled {
    self.push.autobadgeEnabled = true;
    XCTAssertTrue(self.push.autobadgeEnabled, @"autobadgeEnabled should be enabled when set to YES");
    XCTAssertTrue([self.dataStore boolForKey:UAPushBadgeSettingsKey],
                  @"autobadgeEnabled should be stored in standardUserDefaults");

    self.push.autobadgeEnabled = NO;
    XCTAssertFalse(self.push.autobadgeEnabled, @"autobadgeEnabled should be disabled when set to NO");
    XCTAssertFalse([self.dataStore boolForKey:UAPushBadgeSettingsKey],
                   @"autobadgeEnabled should be stored in standardUserDefaults");
}

- (void)testTags {
    NSArray *tags = @[@"tag-one", @"tag-two"];
    [[self.mockChannel expect] setTags:tags];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    self.push.tags = tags;

    [[self.mockChannel expect] tags];
    tags = self.push.tags;
#pragma clang diagnostic pop
    [self.mockChannel verify];
}

- (void)testAddTags {
    NSArray *tags = @[@"tag-one", @"tag-two"];
    [[self.mockChannel expect] addTags:tags];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [self.push addTags:tags];
#pragma clang diagnostic pop
    [self.mockChannel verify];
}

- (void)testAddTag {
    NSString *tag = @"tag";
    [[self.mockChannel expect] addTag:tag];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [self.push addTag:tag];
#pragma clang diagnostic pop
    [self.mockChannel verify];
}

- (void)testRemoveTag {
    NSString *tag = @"tag";
    [[self.mockChannel expect] removeTag:tag];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [self.push removeTag:tag];
#pragma clang diagnostic pop
    [self.mockChannel verify];
}

- (void)testRemoveTags {
    NSArray *tags = @[@"tag-one", @"tag-two"];
    [[self.mockChannel expect] removeTags:tags];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [self.push removeTags:tags];
#pragma clang diagnostic pop
    [self.mockChannel verify];
}

/**
 * Test enabling userPushNotificationsEnabled saves its settings
 * to NSUserDefaults and updates apns registration.
 */
- (void)testUserPushNotificationsEnabled {
    // SETUP
    self.push.userPushNotificationsEnabled = NO;

    // EXPECTATIONS
    __block NSMutableSet *expectedCategories = [NSMutableSet set];
    for (UANotificationCategory *category in self.push.combinedCategories) {
        [expectedCategories addObject:[category asUNNotificationCategory]];
    }
    UANotificationOptions expectedOptions = UANotificationOptionAlert | UANotificationOptionBadge | UANotificationOptionSound;
    [self expectUpdatePushRegistrationWithOptions:expectedOptions categories:expectedCategories];

    // TEST
    self.push.userPushNotificationsEnabled = YES;

    // VERIFY
    XCTAssertTrue(self.push.userPushNotificationsEnabled,
                  @"userPushNotificationsEnabled should be enabled when set to YES");

    XCTAssertTrue([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey],
                  @"userPushNotificationsEnabled should be stored in standardUserDefaults");
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should be called");
}

- (void)testUserPushNotificationsEnabledWhenAppIsHandlingAuthorization {
    // SETUP
    self.config.requestAuthorizationToUseNotifications = NO;
    self.push.userPushNotificationsEnabled = NO;

    // EXPECTATIONS
    [self rejectUpdatePushRegistrationWithOptions];

    // TEST
    self.push.userPushNotificationsEnabled = YES;

    // VERIFY
    XCTAssertTrue(self.push.userPushNotificationsEnabled,
                  @"userPushNotificationsEnabled should be enabled when set to YES");

    XCTAssertTrue([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey],
                  @"userPushNotificationsEnabled should be stored in standardUserDefaults");
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should not be called");
}

/**
 * Test disabling userPushNotificationsEnabled saves its settings
 * to NSUserDefaults and updates push registration.
 */
- (void)testUserPushNotificationsDisabled {
    // SETUP
    self.push.userPushNotificationsEnabled = YES;
    self.push.deviceToken = validDeviceToken;
    self.push.shouldUpdateAPNSRegistration = NO;

    // Make sure we have previously registered types
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsBadge;

    // Make sure push is set to YES
    XCTAssertTrue(self.push.userPushNotificationsEnabled,
                  @"userPushNotificationsEnabled should default to YES");

    [self expectUpdatePushRegistrationWithOptions:UANotificationOptionNone categories:nil];

    // TEST
    self.push.userPushNotificationsEnabled = NO;

    // VERIFY
    XCTAssertFalse(self.push.userPushNotificationsEnabled,
                   @"userPushNotificationsEnabled should be disabled when set to NO");
    XCTAssertFalse([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey],
                   @"userPushNotificationsEnabled should be stored in standardUserDefaults");
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should be called");
}

- (void)testUserPushNotificationsDisabledWhenAppIsHandlingAuthorization {
    // SETUP
    self.config.requestAuthorizationToUseNotifications = NO;

    self.push.userPushNotificationsEnabled = YES;
    self.push.deviceToken = validDeviceToken;
    self.push.shouldUpdateAPNSRegistration = NO;

    // Make sure we have previously registered types
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsBadge;

    // Make sure push is set to YES
    XCTAssertTrue(self.push.userPushNotificationsEnabled,
                  @"userPushNotificationsEnabled should default to YES");

    [self rejectUpdatePushRegistrationWithOptions];

    // TEST
    self.push.userPushNotificationsEnabled = NO;

    // VERIFY
    XCTAssertFalse(self.push.userPushNotificationsEnabled,
                   @"userPushNotificationsEnabled should be disabled when set to NO");
    XCTAssertFalse([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey],
                   @"userPushNotificationsEnabled should be stored in standardUserDefaults");
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should not be called");
}

/**
 * Test enabling or disabling backgroundPushNotificationsEnabled saves its settings
 * to NSUserDefaults and triggers a channel registration update.
 */
- (void)testBackgroundPushNotificationsEnabled {
    self.push.userPushNotificationsEnabled = YES;
    self.push.backgroundPushNotificationsEnabled = NO;

    // TEST
    self.push.backgroundPushNotificationsEnabled = YES;

    // VERIFY
    XCTAssertTrue([self.dataStore boolForKey:UABackgroundPushNotificationsEnabledKey],
                  @"backgroundPushNotificationsEnabled should be stored in standardUserDefaults");

    // EXPECTATIONS
    [[self.mockChannel expect] updateRegistration];

    // TEST
    self.push.backgroundPushNotificationsEnabled = NO;

    // VERIFY
    XCTAssertFalse([self.dataStore boolForKey:UABackgroundPushNotificationsEnabledKey],
                   @"backgroundPushNotificationsEnabled should be stored in standardUserDefaults");

    XCTAssertNoThrow([self.mockChannel verify],  @"should update channel registration");
}

/**
 * Test enabling or disabling pushTokenRegistrationEnabled saves its settings
 * to NSUserDefaults and triggers a channel registration update.
 */
- (void)testPushTokenRegistrationEnabled {
    self.push.pushTokenRegistrationEnabled = NO;

    // TEST
    self.push.pushTokenRegistrationEnabled = YES;

    // VERIFY
    XCTAssertTrue([self.dataStore boolForKey:UAPushTokenRegistrationEnabledKey],
                  @"pushTokenRegistrationEnabled should be stored in standardUserDefaults");

    // EXPECTATIONS
    [[self.mockChannel expect] updateRegistration];

    // TEST
    self.push.pushTokenRegistrationEnabled = NO;

    // VERIFY
    XCTAssertFalse([self.dataStore boolForKey:UAPushTokenRegistrationEnabledKey],
                   @"pushTokenRegistrationEnabled should be stored in standardUserDefaults");

    XCTAssertNoThrow([self.mockChannel verify],  @"should update channel registration");
}

- (void)testSetQuietTime {
    [self.push setQuietTimeStartHour:12 startMinute:30 endHour:14 endMinute:58];

    NSDictionary *quietTime = self.push.quietTime;
    XCTAssertEqualObjects(@"12:30", [quietTime valueForKey:UAPushQuietTimeStartKey],
                          @"Quiet time start is not set correctly");

    XCTAssertEqualObjects(@"14:58", [quietTime valueForKey:UAPushQuietTimeEndKey],
                          @"Quiet time end is not set correctly");

    // Change the time zone
    self.push.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:-3600*3];

    // Make sure the hour and minutes are still the same
    quietTime = self.push.quietTime;
    XCTAssertEqualObjects(@"12:30", [quietTime valueForKey:UAPushQuietTimeStartKey],
                          @"Quiet time start is not set correctly");

    XCTAssertEqualObjects(@"14:58", [quietTime valueForKey:UAPushQuietTimeEndKey],
                          @"Quiet time end is not set correctly");


    // Try to set it to an invalid start hour
    [self.push setQuietTimeStartHour:24 startMinute:30 endHour:14 endMinute:58];

    // Make sure the hour and minutes are still the same
    quietTime = self.push.quietTime;
    XCTAssertEqualObjects(@"12:30", [quietTime valueForKey:UAPushQuietTimeStartKey],
                          @"Quiet time start is not set correctly");

    XCTAssertEqualObjects(@"14:58", [quietTime valueForKey:UAPushQuietTimeEndKey],
                          @"Quiet time end is not set correctly");

    // Try to set it to an invalid end minute
    [self.push setQuietTimeStartHour:12 startMinute:30 endHour:14 endMinute:60];

    // Make sure the hour and minutes are still the same
    quietTime = self.push.quietTime;
    XCTAssertEqualObjects(@"12:30", [quietTime valueForKey:UAPushQuietTimeStartKey],
                          @"Quiet time start is not set correctly");

    XCTAssertEqualObjects(@"14:58", [quietTime valueForKey:UAPushQuietTimeEndKey],
                          @"Quiet time end is not set correctly");
}


- (void)testTimeZone {
    self.push.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"EST"];

    XCTAssertEqualObjects([NSTimeZone timeZoneWithAbbreviation:@"EST"],
                          self.push.timeZone,
                          @"timezone is not being set correctly");

    XCTAssertEqualObjects([[NSTimeZone timeZoneWithAbbreviation:@"EST"] name],
                          [self.dataStore stringForKey:UAPushTimeZoneSettingsKey],
                          @"timezone should be stored in standardUserDefaults");

    // Clear the timezone from preferences
    [self.dataStore removeObjectForKey:UAPushTimeZoneSettingsKey];

    XCTAssertEqualObjects([self.push.defaultTimeZoneForQuietTime abbreviation],
                          [self.push.timeZone abbreviation],
                          @"Timezone should default to defaultTimeZoneForQuietTime");

    XCTAssertNil([self.dataStore stringForKey:UAPushTimeZoneSettingsKey],
                 @"timezone should be able to be cleared in standardUserDefaults");
}

/**
 * Test update apns registration when user notifications are enabled.
 */
- (void)testUpdateAPNSRegistrationUserNotificationsEnabled {
    self.push.userPushNotificationsEnabled = YES;
    self.push.shouldUpdateAPNSRegistration = YES;
    self.push.customCategories = [NSSet set];
    self.push.notificationOptions = UANotificationOptionAlert;
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsAlert;

    // EXPECTATIONS
    __block NSMutableSet *expectedCategories = [NSMutableSet set];
    for (UANotificationCategory *category in self.push.combinedCategories) {
        [expectedCategories addObject:[category asUNNotificationCategory]];
    }

    [self expectUpdatePushRegistrationWithOptions:self.push.notificationOptions categories:expectedCategories];

    // TEST
    [self.push updateAPNSRegistration];

    // VERIFY
    XCTAssertFalse(self.push.shouldUpdateAPNSRegistration, @"Updating APNS registration should set shouldUpdateAPNSRegistration to NO");
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should be called");
}

- (void)testUpdateAPNSRegistrationUserNotificationsEnabledWhenAppIsHandlingAuthorization {
    // SETUP
    self.config.requestAuthorizationToUseNotifications = NO;

    self.push.userPushNotificationsEnabled = YES;
    self.push.shouldUpdateAPNSRegistration = YES;
    self.push.customCategories = [NSSet set];
    self.push.notificationOptions = UANotificationOptionAlert;
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsAlert;

    // EXPECTATIONS
    [self rejectUpdatePushRegistrationWithOptions];

    // TEST
    [self.push updateAPNSRegistration];

    // VERIFY
    XCTAssertFalse(self.push.shouldUpdateAPNSRegistration, @"Updating APNS registration should set shouldUpdateAPNSRegistration to NO");
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should not be called");
}

/**
 * Test enable push notifications updates APNS registration and receives a completion handler callback.
 */
- (void)testEnablePushNotificationsCompletionHandlerCalled {
    self.push.customCategories = [NSSet set];
    self.push.notificationOptions = UANotificationOptionAlert;
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsAlert;

    // EXPECTATIONS
    __block NSMutableSet *expectedCategories = [NSMutableSet set];
    for (UANotificationCategory *category in self.push.combinedCategories) {
        [expectedCategories addObject:[category asUNNotificationCategory]];
    }
    [self expectUpdatePushRegistrationWithOptions:self.push.notificationOptions categories:expectedCategories];

    XCTestExpectation *delegateCalled = [self expectationWithDescription:@"Delegate called"];
    XCTestExpectation *completionHandlerCalled = [self expectationWithDescription:@"Enable push completion handler called"];
    [[[self.mockRegistrationDelegate expect] andDo:^(NSInvocation *invocation) {
        [delegateCalled fulfill];
    }]  notificationRegistrationFinishedWithAuthorizedSettings:self.authorizedNotificationSettings categories:[OCMArg checkWithBlock:^BOOL(id obj) {
        NSSet *categories = (NSSet *)obj;
        return (categories.count == expectedCategories.count);
    }]];

    // TEST
    [self.push enableUserPushNotifications:^(BOOL success) {
        [completionHandlerCalled fulfill];
    }];

    // VERIFY
    [self waitForTestExpectations];
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should be called");
    XCTAssertNoThrow([self.mockRegistrationDelegate verify], @"Registration delegate should be called");
}

- (void)testEnablePushNotificationsCompletionHandlerCalledWhenAppIsHandlingAuthorization {
    // SETUP
    self.config.requestAuthorizationToUseNotifications = NO;

    self.push.customCategories = [NSSet set];
    self.push.notificationOptions = UANotificationOptionAlert;
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsAlert;

    // EXPECTATIONS
    __block NSMutableSet *expectedCategories = [NSMutableSet set];
    for (UANotificationCategory *category in self.push.combinedCategories) {
        [expectedCategories addObject:[category asUNNotificationCategory]];
    }
    [self rejectUpdatePushRegistrationWithOptions];

    XCTestExpectation *delegateCalled = [self expectationWithDescription:@"Delegate called"];
    XCTestExpectation *completionHandlerCalled = [self expectationWithDescription:@"Enable push completion handler called"];
    [[[self.mockRegistrationDelegate expect] andDo:^(NSInvocation *invocation) {
        [delegateCalled fulfill];
    }]  notificationRegistrationFinishedWithAuthorizedSettings:self.authorizedNotificationSettings categories:[OCMArg checkWithBlock:^BOOL(id obj) {
        NSSet *categories = (NSSet *)obj;
        return (categories.count == expectedCategories.count);
    }]];

    // TEST
    [self.push enableUserPushNotifications:^(BOOL success) {
        [completionHandlerCalled fulfill];
    }];

    // VERIFY
    [self waitForExpectationsWithTimeout:1 handler:nil];
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should not be called");
    XCTAssertNoThrow([self.mockRegistrationDelegate verify], @"Registration delegate should be called");
}

/**
 * Test setting authorized types to a new type results in a call to the registration delegate
 */
-(void)testSetAuthorizedTypesCallsRegistrationDelegate {

    UAAuthorizedNotificationSettings expectedSettings = 2;

    XCTestExpectation *delegateCalled = [self expectationWithDescription:@"Delegate called"];

    [[[self.mockRegistrationDelegate expect] andDo:^(NSInvocation *invocation) {
        [delegateCalled fulfill];
    }]  notificationAuthorizedSettingsDidChange:expectedSettings];

    // set authorized types
    self.push.authorizedNotificationSettings = expectedSettings;

    [self waitForTestExpectations];

    XCTAssertNoThrow([self.mockRegistrationDelegate verify]);
}

/**
 * Test receiving a call to application:didRegisterForRemoteNotificationsWithDeviceToken: results in that call being forwarded to the registration delegate
 */
-(void)testPushForwardsDidRegisterForRemoteNotificationsWithDeviceTokenToRegistrationDelegateForeground {
    [[[self.mockAppStateTracker stub] andReturnValue:@(UAApplicationStateActive)] state];

    XCTestExpectation *delegateCalled = [self expectationWithDescription:@"Registration delegate called"];

    [[[self.mockRegistrationDelegate expect] andDo:^(NSInvocation *invocation) {
        [delegateCalled fulfill];
    }]  apnsRegistrationSucceededWithDeviceToken:self.validAPNSDeviceToken];

    // Expect UAPush to update its channel registration
    [[self.mockChannel expect] updateRegistration];

    // TEST
    [self.push application:self.mockApplication didRegisterForRemoteNotificationsWithDeviceToken:self.validAPNSDeviceToken];

    // VERIFY
    [self waitForTestExpectations];

    [self.mockRegistrationDelegate verify];

    // device token also should be set
    XCTAssertTrue([self.push.deviceToken isEqualToString:[UAUtils deviceTokenStringFromDeviceToken:self.validAPNSDeviceToken]]);

    XCTAssertNoThrow([self.mockChannel verify], @"should update channel registration");
}

/**
 * Test receiving a call to application:didRegisterForRemoteNotificationsWithDeviceToken: results in that call being forwarded to the registration delegate
 */
-(void)testPushForwardsDidRegisterForRemoteNotificationsWithDeviceTokenToRegistrationDelegateBackground {
    [[[self.mockAppStateTracker stub] andReturnValue:@(UAApplicationStateBackground)] state];

    // EXPECTATIONS
    [[self.mockRegistrationDelegate expect] apnsRegistrationSucceededWithDeviceToken:self.validAPNSDeviceToken];

    // Expect UAPush to update its channel registration
    [[self.mockChannel expect] updateRegistration];

    // TEST
    [self.push application:self.mockApplication didRegisterForRemoteNotificationsWithDeviceToken:self.validAPNSDeviceToken];

    // VERIFY
    XCTAssertTrue([self.push.deviceToken isEqualToString:[UAUtils deviceTokenStringFromDeviceToken:self.validAPNSDeviceToken]]);

    [self.mockRegistrationDelegate verify];
    XCTAssertNoThrow([self.mockChannel verify], @"should update channel registration");
}

/**
 * Test receiving a call to application:didFailToRegisterForRemoteNotificationsWithError: results in that call being forwarded to the registration delegate
 */
-(void)testPushForwardsDidFailToRegisterForRemoteNotificationsWithDeviceTokenToRegistrationDelegate {
    NSError *error = [NSError errorWithDomain:@"domain" code:100 userInfo:nil];

    XCTestExpectation *delegateCalled = [self expectationWithDescription:@"Registration delegate called"];

    [[[self.mockRegistrationDelegate expect] andDo:^(NSInvocation *invocation) {
        [delegateCalled fulfill];
    }]  apnsRegistrationFailedWithError:error];

    [self.push application:self.mockApplication didFailToRegisterForRemoteNotificationsWithError:error];

    [self waitForTestExpectations];

    XCTAssertNoThrow([self.mockRegistrationDelegate verify]);
}

/**
 * Test setting requireAuthorizationForDefaultCategories requests the correct
 * defaults user notification categories.
 */
- (void)testRequireAuthorizationForDefaultCategories {
    // Clear the custom categories so we can check only Airship categories in comibinedCategories.
    self.push.customCategories = [NSSet set];

    XCTAssertTrue(self.push.combinedCategories.count);

    self.push.requireAuthorizationForDefaultCategories = YES;
    for (UANotificationCategory *category in self.push.combinedCategories) {
        for (UANotificationAction *action in category.actions) {
            // Only check background actions
            if ((action.options & UNNotificationActionOptionForeground) == UANotificationOptionNone) {
                XCTAssertTrue((action.options & UNNotificationActionOptionAuthenticationRequired) > 0, @"Invalid options for action: %@", action.identifier);

            }
        }
    }

    self.push.requireAuthorizationForDefaultCategories = NO;
    for (UANotificationCategory *category in self.push.combinedCategories) {
        for (UANotificationAction *action in category.actions) {
            // Only check background actions
            if ((action.options & UNNotificationActionOptionForeground) == UANotificationOptionNone) {
                XCTAssertFalse((action.options & UNNotificationActionOptionAuthenticationRequired) > 0, @"Invalid options for action: %@", action.identifier);

            }
        }
    }
}

/**
 * Test the user notification categories used to register is the union between
 * the default categories and the custom categories.
 */
- (void)testNotificationCategories {
    self.push.userPushNotificationsEnabled = YES;

    UANotificationCategory *defaultCategory = [UANotificationCategory categoryWithIdentifier:@"defaultCategory" actions:@[]  intentIdentifiers:@[] options:UANotificationCategoryOptionNone];
    UANotificationCategory *customCategory = [UANotificationCategory categoryWithIdentifier:@"customCategory" actions:@[]  intentIdentifiers:@[] options:UANotificationCategoryOptionNone];
    UANotificationCategory *anotherCustomCategory = [UANotificationCategory categoryWithIdentifier:@"anotherCustomCategory" actions:@[] intentIdentifiers:@[] options:UANotificationCategoryOptionNone];

    NSSet *defaultSet = [NSSet setWithArray:@[defaultCategory]];
    [[[self.mockDefaultNotificationCategories stub] andReturn:defaultSet] defaultCategoriesWithRequireAuth:self.push.requireAuthorizationForDefaultCategories];

    NSSet *customSet = [NSSet setWithArray:@[customCategory, anotherCustomCategory]];
    self.push.customCategories = customSet;

    NSSet *expectedSet = [NSSet setWithArray:@[defaultCategory, customCategory, anotherCustomCategory]];
    XCTAssertEqualObjects(self.push.combinedCategories, expectedSet);
}


/**
 * Test update apns registration when user notifications are disabled.
 */
- (void)testUpdateAPNSRegistrationUserNotificationsDisabled {
    // Make sure we have previously registered types
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsBadge;

    self.push.userPushNotificationsEnabled = NO;

    // EXPECTATIONS
    [self expectUpdatePushRegistrationWithOptions:UANotificationOptionNone categories:nil];

    // TEST
    [self.push updateAPNSRegistration];

    // VERIFY
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should be called");
}

- (void)testUpdateAPNSRegistrationUserNotificationsDisabledWhenAppIsHandlingAuthorization {
    // SETUP
    self.config.requestAuthorizationToUseNotifications = NO;

    // Make sure we have previously registered types
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsBadge;

    self.push.userPushNotificationsEnabled = NO;

    // EXPECTATIONS
    [self rejectUpdatePushRegistrationWithOptions];

    // TEST
    [self.push updateAPNSRegistration];

    // VERIFY
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should not be called");
}


/**
 * Test update apns does not register for 0 types if already is registered for none.
 */
- (void)testUpdateAPNSRegistrationPushAlreadyDisabled {
    // SETUP
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsNone;
    self.push.userPushNotificationsEnabled = NO;
    [self.push updateAPNSRegistration];

    // EXPECTATIONS
    // Make sure we do not register for none, if we are
    // already registered for none or it will prompt the user.
    [[[self.mockPushRegistration reject] ignoringNonObjectArgs] updateRegistrationWithOptions:0 categories:OCMOCK_ANY completionHandler:OCMOCK_ANY];

    // TEST
    [self.push updateAPNSRegistration];

    // VERIFY
    [self.mockPushRegistration verify];
}

- (void)testSetBadgeNumberAutoBadgeEnabled {
    // Set the right values so we can check if a device api client call was made or not
    self.push.userPushNotificationsEnabled = YES;
    self.push.autobadgeEnabled = YES;
    self.push.deviceToken = validDeviceToken;

    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE((NSInteger)30)] applicationIconBadgeNumber];

    // EXPECTATIONS
    [[self.mockApplication expect] setApplicationIconBadgeNumber:15];

    // Expect UAPush to update its registration
    [[self.mockChannel expect] updateRegistrationForcefully:YES];

    // TEST
    [self.push setBadgeNumber:15];

    // VERIFY
    XCTAssertNoThrow([self.mockApplication verify],
                     @"should update application icon badge number when its different");

    XCTAssertNoThrow([self.mockChannel verify],
                     @"should update registration so autobadge works");
}

- (void)testSetBadgeNumberNoChange {
    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE((NSInteger)30)] applicationIconBadgeNumber];
    [[self.mockApplication reject] setApplicationIconBadgeNumber:30];

    [self.push setBadgeNumber:30];
    XCTAssertNoThrow([self.mockApplication verify],
                     @"should not update application icon badge number if there is no change");
}

- (void)testSetBadgeNumberAutoBadgeDisabled {
    self.push.userPushNotificationsEnabled = YES;
    self.push.deviceToken = validDeviceToken;

    self.push.autobadgeEnabled = NO;

    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE((NSInteger)30)] applicationIconBadgeNumber];
    [[self.mockApplication expect] setApplicationIconBadgeNumber:15];

    // Reject device api client registration because autobadge is not enabled
    [[self.mockChannel reject] updateRegistrationForcefully:YES];

    [self.push setBadgeNumber:15];
    XCTAssertNoThrow([self.mockApplication verify],
                     @"should update application icon badge number when its different");

    XCTAssertNoThrow([self.mockChannel verify],
                     @"should not update registration because autobadge is disabled");
}

- (void)testResetBadge {
    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE((NSInteger)30)] applicationIconBadgeNumber];
    [[self.mockApplication expect] setApplicationIconBadgeNumber:0];

    [self.push resetBadge];
    XCTAssertNoThrow([self.mockApplication verify],
                     @"should set application icon badge number to 0");
}

- (void)testResetBadgeNumberNoChange {
    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE((NSInteger)0)] applicationIconBadgeNumber];
    [[self.mockApplication reject] setApplicationIconBadgeNumber:0];

    [self.push resetBadge];
    XCTAssertNoThrow([self.mockApplication verify],
                     @"should not update application icon badge number if there is no change");
}

/**
 * Test quietTimeEnabled.
 */
- (void)testSetQuietTimeEnabled {
    [self.dataStore removeObjectForKey:UAPushQuietTimeEnabledSettingsKey];
    XCTAssertFalse(self.push.quietTimeEnabled, @"QuietTime should be disabled");

    self.push.quietTimeEnabled = YES;
    XCTAssertTrue(self.push.quietTimeEnabled, @"QuietTime should be enabled");

    self.push.quietTimeEnabled = NO;
    XCTAssertFalse(self.push.quietTimeEnabled, @"QuietTime should be disabled");
}

/**
 * Test setting the default userPushNotificationsEnabled value.
 */
- (void)testUserPushNotificationsEnabledByDefault {
    self.push.userPushNotificationsEnabledByDefault = YES;
    XCTAssertTrue(self.push.userPushNotificationsEnabled, @"default user notification value taking affect.");

    [self.dataStore removeAll];

    self.push.userPushNotificationsEnabledByDefault = NO;
    XCTAssertFalse(self.push.userPushNotificationsEnabled, @"default user notification value not taking affect.");
}

/**
 * Test setting the default backgroundPushNotificationEnabled value.
 */
- (void)testBackgroundPushNotificationsEnabledByDefault {
    self.push.backgroundPushNotificationsEnabledByDefault = YES;
    XCTAssertTrue(self.push.backgroundPushNotificationsEnabled, @"default background notification value not taking affect.");

    self.push.backgroundPushNotificationsEnabledByDefault = NO;
    XCTAssertFalse(self.push.backgroundPushNotificationsEnabled, @"default background notification value not taking affect.");
}

/**
 * Test update registration when shouldUpdateAPNSRegistration is true, updates
 * apns registration and not channel registration.
 */
- (void)testUpdateRegistrationShouldUpdateAPNS {
    self.push.shouldUpdateAPNSRegistration = YES;

    // Reject any device registration
    [[self.mockChannel reject] updateRegistration];

    // Update the registration
    [self.push updateRegistration];

    // Verify it reset the flag
    XCTAssertFalse(self.push.shouldUpdateAPNSRegistration, @"updateRegistration should handle APNS registration updates if shouldUpdateAPNSRegistration is YES.");
    XCTAssertNoThrow([self.mockChannel verify], @"should not update channel registration");
}

- (void)testEnableChannelCreation {
    [[self.mockChannel expect] enableChannelCreation];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [self.push enableChannelCreation];
#pragma clang diagnostic pop
    [self.mockChannel verify];
}

/**
 * Test when backgroundPushNotificationsAllowed is YES when
 * device token is available, remote-notification background mode is enabled,
 * backgroundRefreshStatus is allowed, backgroundPushNotificationsEnabled is
 * enabled and pushTokenRegistrationEnabled is YES.
 */
- (void)testBackgroundPushNotificationsAllowed {
    self.push.deviceToken = validDeviceToken;
    self.push.backgroundPushNotificationsEnabled = YES;
    self.push.pushTokenRegistrationEnabled = YES;
    [[[self.mockAirship stub] andReturnValue:OCMOCK_VALUE(YES)] remoteNotificationBackgroundModeEnabled];
    [[[self.mockApplication stub] andReturnValue:@(UIBackgroundRefreshStatusAvailable)] backgroundRefreshStatus];
    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE(YES)] isRegisteredForRemoteNotifications];

    XCTAssertTrue(self.push.backgroundPushNotificationsAllowed,
                  @"BackgroundPushNotificationsAllowed should be YES");
}

/**
 * Test when backgroundPushNotificationsAllowed is NO when the device token is
 * missing.
 */
- (void)testBackgroundPushNotificationsDisallowedNoDeviceToken {
    self.push.userPushNotificationsEnabled = YES;
    self.push.backgroundPushNotificationsEnabled = YES;
    [[[self.mockAirship stub] andReturnValue:OCMOCK_VALUE(YES)] remoteNotificationBackgroundModeEnabled];
    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE(YES)] isRegisteredForRemoteNotifications];
    [[[self.mockApplication stub] andReturnValue:@(UIBackgroundRefreshStatusAvailable)] backgroundRefreshStatus];

    self.push.deviceToken = nil;
    XCTAssertFalse(self.push.backgroundPushNotificationsAllowed,
                   @"BackgroundPushNotificationsAllowed should be NO");
}

/**
 * Test when backgroundPushNotificationsAllowed is NO when backgroundPushNotificationsAllowed
 * is disabled.
 */
- (void)testBackgroundPushNotificationsDisallowedDisabled {
    self.push.userPushNotificationsEnabled = YES;
    [[[self.mockAirship stub] andReturnValue:OCMOCK_VALUE(YES)] remoteNotificationBackgroundModeEnabled];
    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE(YES)] isRegisteredForRemoteNotifications];
    [[[self.mockApplication stub] andReturnValue:@(UIBackgroundRefreshStatusAvailable)] backgroundRefreshStatus];
    self.push.deviceToken = validDeviceToken;


    self.push.backgroundPushNotificationsEnabled = NO;
    XCTAssertFalse(self.push.backgroundPushNotificationsAllowed,
                   @"BackgroundPushNotificationsAllowed should be NO");
}

/**
 * Test when backgroundPushNotificationsAllowed is NO when the application is not
 * configured with remote-notification background mode.
 */
- (void)testBackgroundPushNotificationsDisallowedBackgroundNotificationDisabled {
    self.push.userPushNotificationsEnabled = YES;
    self.push.backgroundPushNotificationsEnabled = YES;
    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE(YES)] isRegisteredForRemoteNotifications];
    [[[self.mockApplication stub] andReturnValue:@(UIBackgroundRefreshStatusAvailable)] backgroundRefreshStatus];
    self.push.deviceToken = validDeviceToken;

    [[[self.mockAirship stub] andReturnValue:OCMOCK_VALUE(NO)] remoteNotificationBackgroundModeEnabled];
    XCTAssertFalse(self.push.backgroundPushNotificationsAllowed,
                   @"BackgroundPushNotificationsAllowed should be NO");
}

/**
 * Test when backgroundPushNotificationsAllowed is NO when backgroundRefreshStatus is invalid.
 */
- (void)testBackgroundPushNotificationsDisallowedInvalidBackgroundRefreshStatus {
    self.push.userPushNotificationsEnabled = YES;
    self.push.backgroundPushNotificationsEnabled = YES;
    [[[self.mockAirship stub] andReturnValue:OCMOCK_VALUE(YES)] remoteNotificationBackgroundModeEnabled];
    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE(YES)] isRegisteredForRemoteNotifications];
    self.push.deviceToken = validDeviceToken;

    [[[self.mockApplication stub] andReturnValue:@(UIBackgroundRefreshStatusRestricted)] backgroundRefreshStatus];

    XCTAssertFalse(self.push.backgroundPushNotificationsAllowed,
                   @"BackgroundPushNotificationsAllowed should be NO");
}

/**
 * Test that backgroundPushNotificationsAllowed is NO when not registered for remote notifications.
 */
- (void)testBackgroundPushNotificationsDisallowedNotRegisteredForRemoteNotifications {
    self.push.backgroundPushNotificationsEnabled = YES;
    [[[self.mockApplication stub] andReturnValue:@(UIBackgroundRefreshStatusAvailable)] backgroundRefreshStatus];
    [[[self.mockAirship stub] andReturnValue:OCMOCK_VALUE(YES)] remoteNotificationBackgroundModeEnabled];
    self.push.deviceToken = validDeviceToken;

    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE(NO)] isRegisteredForRemoteNotifications];
    XCTAssertFalse(self.push.backgroundPushNotificationsAllowed,
                   @"BackgroundPushNotificationsAllowed should be NO");
}

/**
 * Test when backgroundPushNotificationsAllowed is NO when
 * pushTokenRegistrationEnabled is NO.
 */
- (void)testBackgroundPushNotificationsPushTokenRegistrationEnabledNo {
    self.push.deviceToken = validDeviceToken;
    self.push.backgroundPushNotificationsEnabled = YES;
    self.push.pushTokenRegistrationEnabled = NO;
    [[[self.mockAirship stub] andReturnValue:OCMOCK_VALUE(YES)] remoteNotificationBackgroundModeEnabled];
    [[[self.mockApplication stub] andReturnValue:@(UIBackgroundRefreshStatusAvailable)] backgroundRefreshStatus];
    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE(YES)] isRegisteredForRemoteNotifications];

    XCTAssertFalse(self.push.backgroundPushNotificationsAllowed,
                   @"BackgroundPushNotificationsAllowed should be NO");
}

/**
 * Test that UserPushNotificationAllowed is NO when there are no authorized notification types set
 */
-(void)testUserPushNotificationsAllowedNo {
    self.push.userPushNotificationsEnabled = YES;
    self.push.pushTokenRegistrationEnabled = NO;
    self.push.deviceToken = validDeviceToken;
    [[[self.mockApplication stub] andReturnValue:OCMOCK_VALUE(YES)] isRegisteredForRemoteNotifications];

    XCTAssertFalse(self.push.userPushNotificationsAllowed,
                   @"UserPushNotificationsAllowed should be NO");
}

/**
 * Test applicationDidTransitionToForeground, when run at launch, doesn't register channel
 */
- (void)testApplicationDidTransitionToForeground {
    // SETUP
    self.push.userPushNotificationsEnabled = YES;
    self.push.notificationOptions = UANotificationOptionAlert;

    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsAlert;
    UAAuthorizedNotificationSettings expectedSettings = UAAuthorizedNotificationSettingsAlert;

    // EXPECTATIONS
    [[self.mockChannel reject] updateRegistration];

    __block NSMutableSet *expectedCategories = [NSMutableSet set];
    for (UANotificationCategory *category in self.push.combinedCategories) {
        [expectedCategories addObject:[category asUNNotificationCategory]];
    }
    UANotificationOptions expectedOptions = UANotificationOptionAlert;
    [self expectUpdatePushRegistrationWithOptions:expectedOptions categories:expectedCategories];

    [[[self.mockAppStateTracker expect] andReturnValue:@(UAApplicationStateActive)] state];

    // TEST
    [self.push applicationDidTransitionToForeground];

    // VERIFY
    XCTAssertTrue(self.push.userPromptedForNotifications);
    XCTAssertEqual(self.push.authorizedNotificationSettings, expectedSettings);
    XCTAssertNoThrow([self.mockChannel verify], @"Channel registration should not be updated");
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should be called");
}

- (void)testApplicationDidTransitionToForegroundWhenAppIsHandlingAuthorization {
    // SETUP
    self.config.requestAuthorizationToUseNotifications = NO;
    self.push.userPushNotificationsEnabled = YES;
    self.push.notificationOptions = UANotificationOptionAlert;

    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsAlert;
    UAAuthorizedNotificationSettings expectedSettings = UAAuthorizedNotificationSettingsAlert;

    // EXPECTATIONS
    [[self.mockChannel expect] updateRegistration];

    [self rejectUpdatePushRegistrationWithOptions];

    [[[self.mockAppStateTracker expect] andReturnValue:@(UAApplicationStateActive)] state];

    // TEST
    [self.push applicationDidTransitionToForeground];

    // VERIFY
    XCTAssertTrue(self.push.userPromptedForNotifications);
    XCTAssertEqual(self.push.authorizedNotificationSettings, expectedSettings);

    XCTAssertNoThrow([self.mockChannel verify], @"[UAChannel updateRegistration] should be called");
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should not be called");
}

-(void)testApplicationBackgroundRefreshStatusChangedBackgroundAvailable {
    // SETUP
    [[[self.mockApplication stub] andReturnValue:@(UIBackgroundRefreshStatusAvailable)] backgroundRefreshStatus];

    // EXPECTATIONS
    [[self.mockApplication expect] registerForRemoteNotifications];

    // TEST
    [self.push applicationBackgroundRefreshStatusChanged];

    // VERIFY
    XCTAssertNoThrow([self.mockApplication verify], @"[UIApplication registerForRemoteNotifications] should be called");
}

-(void)testApplicationBackgroundRefreshStatusChangedBackgroundDenied {
    // SETUP
    [[[self.mockApplication stub] andReturnValue:@(UIBackgroundRefreshStatusDenied)] backgroundRefreshStatus];
    // set an option so channel registration happens
    self.push.notificationOptions = UANotificationOptionSound;
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsSound;

    // EXPECTATIONS
    __block NSMutableSet *expectedCategories = [NSMutableSet set];
    for (UANotificationCategory *category in self.push.combinedCategories) {
        [expectedCategories addObject:[category asUNNotificationCategory]];
    }
    [self expectUpdatePushRegistrationWithOptions:UANotificationOptionSound categories:expectedCategories];

    // TEST
    [self.push applicationBackgroundRefreshStatusChanged];

    // VERIFY
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should be called");
}

-(void)testApplicationBackgroundRefreshStatusChangedBackgroundDeniedWhenAppIsHandlingAuthorization {
    // SETUP
    self.config.requestAuthorizationToUseNotifications = NO;
    [[[self.mockApplication stub] andReturnValue:@(UIBackgroundRefreshStatusDenied)] backgroundRefreshStatus];
    // set an option so channel registration happens
    self.push.notificationOptions = UANotificationOptionSound;
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsSound;

    // EXPECTATIONS
    [self rejectUpdatePushRegistrationWithOptions];

    // TEST
    [self.push applicationBackgroundRefreshStatusChanged];

    // VERIFY
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should not be called");
}

/**
 * Test applicationDidEnterBackground clears the notification.
 */
- (void)testApplicationDidEnterBackground {
    self.push.launchNotificationResponse = [[UANotificationResponse alloc] init];

    [self.push applicationDidEnterBackground];
    XCTAssertNil(self.push.launchNotificationResponse, @"applicationDidEnterBackground should clear the launch notification");
}

/**
 * Test registration succeeded with channels and an up to date payload
 */
- (void)testRegistrationSucceeded {
    self.push.deviceToken = validDeviceToken;
    [[[self.mockChannel stub] andReturn:@"someChannelID"] identifier];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [[self.mockRegistrationDelegate expect] registrationSucceededForChannelID:@"someChannelID" deviceToken:validDeviceToken];
#pragma clang diagnostic pop
    [self.notificationCenter postNotificationName:UAChannelUpdatedEvent
                                           object:nil
                                         userInfo:@{ UAChannelCreatedEventExistingKey: @(NO),
                                                     UAChannelCreatedEventChannelKey:@"someChannelID"}];


    XCTAssertNoThrow([self.mockRegistrationDelegate verify], @"Delegate should be called");
}

/**
 * Test registration succeeded with no channel ID
 */
- (void)testRegistrationSucceededWithNoChannelID {
    self.push.deviceToken = validDeviceToken;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [[self.mockRegistrationDelegate reject] registrationSucceededForChannelID:@"someChannelID" deviceToken:validDeviceToken];
#pragma clang diagnostic pop
    [[self.mockChannel reject] updateRegistration];

    // Call with an empty payload.  Should be different then the UAPush generated payload
    [self.notificationCenter postNotificationName:UAChannelUpdatedEvent
                                           object:nil
                                         userInfo:nil];

    XCTAssertNoThrow([self.mockRegistrationDelegate verify], @"Delegate should not be called");
    XCTAssertNoThrow([self.mockChannel verify], @"Registration should not happen");
}


/**
 * Test registration failed
 */
- (void)testRegistrationFailed {
    XCTestExpectation *delegateCalled = [self expectationWithDescription:@"Delegate called"];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [[[self.mockRegistrationDelegate expect] andDo:^(NSInvocation *invocation) {
        [delegateCalled fulfill];
    }] registrationFailed];
#pragma clang diagnostic pop

    [self.notificationCenter postNotificationName:UAChannelRegistrationFailedEvent
                                           object:nil
                                         userInfo:nil];
    [self waitForTestExpectations];

    XCTAssertNoThrow([self.mockRegistrationDelegate verify], @"Delegate should be called");
}

/**
 * Test migrating the userNotificationEnabled key no ops when it's already set.
 */
- (void)testMigrateNewRegistrationFlowAlreadySet {
    // Set the UAUserPushNotificationsEnabledKey setting to NO
    [self.dataStore setBool:NO forKey:UAUserPushNotificationsEnabledKey];

    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsAlert;

    // Force a migration
    [self.dataStore removeObjectForKey:UAPushEnabledSettingsMigratedKey];
    [self.push migratePushSettings];

    // Verify its still NO
    XCTAssertFalse([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey]);
}
/**
 * Test migrating the userNotificationEnabled key does not set if the
 * current authorization status is denied.
 */
- (void)testMigrateNewRegistrationFlowDisabled {
    // Clear the UAUserPushNotificationsEnabledKey setting
    [self.dataStore removeObjectForKey:UAUserPushNotificationsEnabledKey];
    [self.dataStore removeObjectForKey:UAPushEnabledSettingsMigratedKey];

    self.authorizationStatus = UAAuthorizationStatusDenied;

    [self.push migratePushSettings];

    // Verify it was not set
    XCTAssertNil([self.dataStore objectForKey:UAUserPushNotificationsEnabledKey]);
}

/**
 * Test migrating the userNotificationEnabled key does set to YES if the
 * current notification types is not none.
 */
- (void)testMigrateNewRegistrationFlowEnabled {
    // Clear the UAUserPushNotificationsEnabledKey setting
    [self.dataStore removeObjectForKey:UAUserPushNotificationsEnabledKey];
    [self.dataStore removeObjectForKey:UAPushEnabledSettingsMigratedKey];

    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsAlert;

    [self.push migratePushSettings];

    // Verify it was set to YES
    XCTAssertTrue([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey]);
}

/**
 * Test migrating the UAUserPushNotificationsEnabledKey sets to the value
 * of the previous UAPushEnabledKey.
 */
- (void)testMigrateNewRegistrationFlowPreviousUAPushEnabledKeyWasSet {
    // Reset for migration
    [self.dataStore removeObjectForKey:UAUserPushNotificationsEnabledKey];
    [self.dataStore removeObjectForKey:UAPushEnabledSettingsMigratedKey];
    // Set the previous UAPushEnabledKey setting to YES
    [self.dataStore setValue:@YES forKey:UAPushEnabledKey];

    [self.push migratePushSettings];

    // Verify it was set to YES
    XCTAssertTrue([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey]);
    XCTAssertNil([self.dataStore objectForKey:UAPushEnabledKey]);

    // Reset for migration
    [self.dataStore removeObjectForKey:UAUserPushNotificationsEnabledKey];
    [self.dataStore removeObjectForKey:UAPushEnabledSettingsMigratedKey];
    // Set the previous UAPushEnabledKey setting to NO
    [self.dataStore setValue:@NO forKey:UAPushEnabledKey];

    [self.push migratePushSettings];

    // Verify it was set to NO
    XCTAssertFalse([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey]);
    XCTAssertNil([self.dataStore objectForKey:UAPushEnabledKey]);
}

/**
 * Test migrating only performs once.
 */
- (void)testMigrateNewRegistrationFlowOnlyOnce {
    // Clear the UAUserPushNotificationsEnabledKey setting
    [self.dataStore removeObjectForKey:UAUserPushNotificationsEnabledKey];
    [self.dataStore removeObjectForKey:UAPushEnabledSettingsMigratedKey];

    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsAlert;

    [self.push migratePushSettings];

    // Verify it was set to YES
    XCTAssertTrue([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey]);
    XCTAssertTrue([self.dataStore boolForKey:UAPushEnabledSettingsMigratedKey]);

    // Clear the UAUserPushNotificationsEnabledKey setting
    [self.dataStore removeObjectForKey:UAUserPushNotificationsEnabledKey];

    [self.push migratePushSettings];

    // Should not enable it the second time
    XCTAssertFalse([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey]);
}

/**
 * Test handleRemoteNotification when auto badge is disabled does
 * not set the badge on the application
 */
- (void)testHandleNotificationAutoBadgeDisabled {
    self.push.autobadgeEnabled = NO;
    [[self.mockApplication reject] setApplicationIconBadgeNumber:2];

    UANotificationContent *notificationContent = [UANotificationContent notificationWithNotificationInfo:self.notification];

    // TEST
    [self.push handleRemoteNotification:notificationContent foreground:YES completionHandler:^(UIBackgroundFetchResult result) {}];
    [self.push handleRemoteNotification:notificationContent foreground:NO completionHandler:^(UIBackgroundFetchResult result) {}];

    // VERIFY
    XCTAssertNoThrow([self.mockApplication verify]);
}

/**
 * Test handleRemoteNotification when auto badge is enabled sets the badge
 * only when a notification comes in while the app is in the foreground
 */
- (void)testHandleNotificationAutoBadgeEnabled {
    self.push.autobadgeEnabled = YES;

    UANotificationContent *notificationContent = [UANotificationContent notificationWithNotificationInfo:self.notification];

    [[self.mockApplication expect] setApplicationIconBadgeNumber:2];
    [self.push handleRemoteNotification:notificationContent foreground:YES completionHandler:^(UIBackgroundFetchResult result) {}];
    XCTAssertNoThrow([self.mockApplication verify], @"[UIApplication setApplicationIconBadgeNumber] should be called");

    [[self.mockApplication reject] setApplicationIconBadgeNumber:2];
    [self.push handleRemoteNotification:notificationContent foreground:NO completionHandler:^(UIBackgroundFetchResult result) {}];
    XCTAssertNoThrow([self.mockApplication verify], @"[UIApplication setApplicationIconBadgeNumber] should not be called");
}

/**
 * Test handleNotificationResponse sets the launched notificaitno response if
 * its the default identifier.
 */
- (void)testHandleNotificationLaunchNotification {
    self.push.launchNotificationResponse = nil;

    UANotificationResponse *response = [UANotificationResponse notificationResponseWithNotificationInfo:self.notification
                                                                                       actionIdentifier:UANotificationDefaultActionIdentifier
                                                                                           responseText:nil];

    [self.push handleNotificationResponse:response completionHandler:^{}];

    XCTAssertEqual(self.push.launchNotificationResponse, response);
}

/**
 * Test handleRemoteNotification when foreground and autobadge is enabled.
 */
- (void)testHandleRemoteNotificationForegroundAutobadgeEnabled {
    UANotificationContent *expectedNotificationContent = [UANotificationContent notificationWithNotificationInfo:self.notification];

    self.push.autobadgeEnabled = YES;

    // Application should set icon badge number when autobadge is enabled
    [[self.mockApplication expect] setApplicationIconBadgeNumber:expectedNotificationContent.badge.integerValue];

    __block NSNotification *notification;

    XCTestExpectation *notificationFired = [self expectationWithDescription:@"Notification event fired"];
    [self.notificationCenter addObserverForName:UAReceivedForegroundNotificationEvent object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        notification = note;
        [notificationFired fulfill];
    }];

    [[self.mockPushDelegate expect] receivedForegroundNotification:expectedNotificationContent completionHandler:[OCMArg checkWithBlock:^BOOL(id obj) {
        void (^handler)(void) = obj;
        handler();
        return YES;
    }]];

    [[self.mockPushDelegate reject] receivedBackgroundNotification:expectedNotificationContent completionHandler:OCMOCK_ANY];

    XCTestExpectation *completionHandlerCalledExpectation = [self expectationWithDescription:@"handleRemoteNotification completionHandler should be called"];

    // TEST
    [self.push handleRemoteNotification:expectedNotificationContent foreground:YES completionHandler:^(UIBackgroundFetchResult result) {
        [completionHandlerCalledExpectation fulfill];
    }];

    // VERIFY
    [self waitForTestExpectations];

    XCTAssertEqualObjects(expectedNotificationContent.notificationInfo, notification.userInfo);

    [self.mockApplication verify];
    [self.mockPushDelegate verify];
}

/**
 * Test handleRemoteNotification when foreground and autobadge is disabled.
 */
- (void)testHandleRemoteNotificationForegroundAutobadgeDisabled {
    UANotificationContent *expectedNotificationContent = [UANotificationContent notificationWithNotificationInfo:self.notification];

    self.push.autobadgeEnabled = NO;

    // Application should set icon badge number when autobadge is enabled
    [[self.mockApplication reject] setApplicationIconBadgeNumber:expectedNotificationContent.badge.integerValue];

    __block NSNotification *notification;

    XCTestExpectation *notificationFired = [self expectationWithDescription:@"Notification event fired"];
    [self.notificationCenter addObserverForName:UAReceivedForegroundNotificationEvent object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        notification = note;
        [notificationFired fulfill];
    }];

    [[self.mockPushDelegate expect] receivedForegroundNotification:expectedNotificationContent completionHandler:[OCMArg checkWithBlock:^BOOL(id obj) {
        void (^handler)(void) = obj;
        handler();
        return YES;
    }]];

    [[self.mockPushDelegate reject] receivedBackgroundNotification:expectedNotificationContent completionHandler:OCMOCK_ANY];

    XCTestExpectation *completionHandlerCalledExpectation = [self expectationWithDescription:@"handleRemoteNotification completionHandler should be called"];

    // TEST
    [self.push handleRemoteNotification:expectedNotificationContent foreground:YES completionHandler:^(UIBackgroundFetchResult result) {
        [completionHandlerCalledExpectation fulfill];
    }];

    // VERIFY
    [self waitForTestExpectations];

    XCTAssertEqualObjects(expectedNotificationContent.notificationInfo, notification.userInfo);

    [self.mockApplication verify];
    XCTAssertNoThrow([self.mockPushDelegate verify], @"push delegate should be called");
}

/**
 * Test handleRemoteNotification when background push.
 */
- (void)testHandleRemoteNotificationBackground {
    UANotificationContent *expectedNotificationContent = [UANotificationContent notificationWithNotificationInfo:self.notification];

    __block NSNotification *notification;

    XCTestExpectation *notificationFired = [self expectationWithDescription:@"Notification event fired"];
    [self.notificationCenter addObserverForName:UAReceivedBackgroundNotificationEvent object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        notification = note;
        [notificationFired fulfill];
    }];

    [[self.mockPushDelegate reject] receivedForegroundNotification:expectedNotificationContent completionHandler:OCMOCK_ANY];

    [[self.mockPushDelegate expect] receivedBackgroundNotification:expectedNotificationContent completionHandler:[OCMArg checkWithBlock:^BOOL(id obj) {
        void (^handler)(void) = obj;
        handler();
        return YES;
    }]];

    XCTestExpectation *completionHandlerCalledExpectation = [self expectationWithDescription:@"handleRemoteNotification completionHandler should be called"];

    // TEST
    [self.push handleRemoteNotification:expectedNotificationContent foreground:NO completionHandler:^(UIBackgroundFetchResult result) {
        [completionHandlerCalledExpectation fulfill];
    }];

    // VERIFY
    [self waitForTestExpectations];

    XCTAssertEqualObjects(expectedNotificationContent.notificationInfo, notification.userInfo);
    XCTAssertNoThrow([self.mockPushDelegate verify], @"push delegate should be called");
}

/**
 * Test handleRemoteNotification when no delegate is set.
 */
- (void)testHandleRemoteNotificationNoDelegate {
    UANotificationContent *expectedNotificationContent = [UANotificationContent notificationWithNotificationInfo:self.notification];

    self.push.pushNotificationDelegate = nil;

    XCTestExpectation *completionHandlerCalledExpectation = [self expectationWithDescription:@"handleRemoteNotification completionHandler should be called"];

    __block NSNotification *notification;

    XCTestExpectation *notificationFired = [self expectationWithDescription:@"Notification event fired"];
    [self.notificationCenter addObserverForName:UAReceivedForegroundNotificationEvent object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        notification = note;
        [notificationFired fulfill];
    }];

    // TEST
    [self.push handleRemoteNotification:expectedNotificationContent foreground:YES completionHandler:^(UIBackgroundFetchResult result) {
        [completionHandlerCalledExpectation fulfill];
        XCTAssertEqual(result, UIBackgroundFetchResultNoData);
    }];

    // VERIFY
    [self waitForTestExpectations];
    XCTAssertEqualObjects(expectedNotificationContent.notificationInfo, notification.userInfo);
}

/**
 * Test handleNotificationResponse when launched from push.
 */
- (void)testHandleNotificationResponseLaunchedFromPush {
    UANotificationResponse *expectedNotificationLaunchFromPush = [UANotificationResponse notificationResponseWithNotificationInfo:self.notification
                                                                                                                 actionIdentifier:UANotificationDefaultActionIdentifier
                                                                                                                     responseText:@"test_response_text"];
    // delegate needs to be unresponsive to receivedNotificationResponse callback
    self.push.pushNotificationDelegate = nil;

    __block NSNotification *notification;

    XCTestExpectation *notificationFired = [self expectationWithDescription:@"Notification event fired"];
    [self.notificationCenter addObserverForName:UAReceivedNotificationResponseEvent object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        notification = note;
        [notificationFired fulfill];
    }];

    // Call handleNotificationResponse
    [self.push handleNotificationResponse:expectedNotificationLaunchFromPush completionHandler:^{
    }];

    [self waitForTestExpectations];

    // Check that the launchNotificationReponse is set to expected response
    XCTAssertEqualObjects(self.push.launchNotificationResponse, expectedNotificationLaunchFromPush);
    XCTAssertEqualObjects(expectedNotificationLaunchFromPush.notificationContent.notificationInfo, notification.userInfo);
}

/**
 * Test handleNotificationResponse when not launched from push.
 */
- (void)testHandleNotificationResponseNotLaunchedFromPush {
    UANotificationResponse *expectedNotificationNotLaunchedFromPush = [UANotificationResponse notificationResponseWithNotificationInfo:self.notification
                                                                                                                      actionIdentifier:@"test_action_identifier"
                                                                                                                          responseText:@"test_response_text"];

    [[self.mockPushDelegate expect] receivedNotificationResponse:OCMOCK_ANY completionHandler:[OCMArg checkWithBlock:^BOOL(id obj) {
        void (^handler)(void) = obj;
        handler();
        return YES;
    }]];

    XCTestExpectation *completionHandlerCalledExpectation = [self expectationWithDescription:@"handleRemoteNotification completionHandler should be called"];

    __block NSNotification *notification;

    XCTestExpectation *notificationFired = [self expectationWithDescription:@"Notification event fired"];
    [self.notificationCenter addObserverForName:UAReceivedNotificationResponseEvent object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        notification = note;
        [notificationFired fulfill];
    }];

    // TEST
    [self.push handleNotificationResponse:expectedNotificationNotLaunchedFromPush completionHandler:^{
        [completionHandlerCalledExpectation fulfill];
    }];

    // VERIFY
    [self waitForTestExpectations];
    XCTAssertNil(self.push.launchNotificationResponse);
    XCTAssertNoThrow([self.mockPushDelegate verify], @"push delegate should be called");
    XCTAssertEqualObjects(expectedNotificationNotLaunchedFromPush.notificationContent.notificationInfo, notification.userInfo);
}

/**
 * Test handleNotificationResponse no delegate set.
 */
- (void)testHandleNotificationResponse {
    self.push.pushNotificationDelegate = nil;

    UANotificationResponse *expectedNotification = [UANotificationResponse notificationResponseWithNotificationInfo:self.notification
                                                                                                   actionIdentifier:@"test_action_identifier"
                                                                                                       responseText:@"test_response_text"];

    XCTestExpectation *completionHandlerCalledExpectation = [self expectationWithDescription:@"handleRemoteNotification completionHandler should be called"];

    // TEST
    [self.push handleNotificationResponse:expectedNotification completionHandler:^{
        [completionHandlerCalledExpectation fulfill];
    }];

    // VERIFY
    [self waitForTestExpectations];
    XCTAssertNil(self.push.launchNotificationResponse);
}

/**
 * Test presentationOptionsForNotification when delegate method is unimplemented.
 */
- (void)testPresentationOptionsForNotificationNoDelegate {

    self.push.defaultPresentationOptions = UNNotificationPresentationOptionAlert;
    self.push.pushNotificationDelegate = nil;

    [[[self.mockAirship stub] andReturn:self.push] push];

    UNNotificationPresentationOptions presentationOptions = [self.push presentationOptionsForNotification:self.mockUNNotification];

    XCTAssertEqual(presentationOptions, self.push.defaultPresentationOptions);
}

/**
 * Test presentationOptionsForNotification when delegate method is implemented.
 */
- (void)testPresentationOptionsForNotification {

    [[[self.mockAirship stub] andReturn:self.push] push];

    [[[self.mockPushDelegate stub] andReturnValue:OCMOCK_VALUE(UNNotificationPresentationOptionAlert)] extendPresentationOptions:UNNotificationPresentationOptionNone notification:self.mockUNNotification];

    UNNotificationPresentationOptions result = [self.push presentationOptionsForNotification:self.mockUNNotification];

    XCTAssertEqual(result, UNNotificationPresentationOptionAlert);
}

/**
 * Test presentationOptionsForNotification when notification contains foreground options and delegate method is unimplemented.
 */
- (void)testPresentationOptionsForNotificationWithForegroundOptionsWithoutDelegate {
    // SETUP
    NSArray *array = @[@"alert", @"sound", @"badge"];
    [[[self.mockUserInfo stub] andReturnValue:OCMOCK_VALUE(array)] objectForKey:@"foreground_presentation"];
    self.push.pushNotificationDelegate = nil;

    // EXPECTATIONS
    UNNotificationPresentationOptions options = UNNotificationPresentationOptionAlert | UNNotificationPresentationOptionSound | UNNotificationPresentationOptionBadge;

    // TEST
    UNNotificationPresentationOptions result = [self.push presentationOptionsForNotification:self.mockUNNotification];

    // VERIFY
    XCTAssertEqual(result, options);
}

/**
 * Test presentationOptionsForNotification when notification foreground options array is empty and delegate method is unimplemented.
 */
- (void)testPresentationOptionsForNotificationWithoutForegroundOptionsWithoutDelegate {
    // SETUP
    NSArray *array = @[];
    [[[self.mockUserInfo stub] andReturnValue:OCMOCK_VALUE(array)] objectForKey:@"foreground_presentation"];
    self.push.defaultPresentationOptions = UNNotificationPresentationOptionAlert;
    self.push.pushNotificationDelegate = nil;

    // EXPECTATIONS
    UNNotificationPresentationOptions options = UNNotificationPresentationOptionAlert;

    // TEST
    UNNotificationPresentationOptions result = [self.push presentationOptionsForNotification:self.mockUNNotification];

    // VERIFY
    XCTAssertEqual(result, options);
}

/**
 * Test on first launch when user has not been prompted for notification.
 */
- (void)testNotificationNotPrompted {
    self.push.authorizedNotificationSettings = UAAuthorizedNotificationSettingsNone;
    XCTAssertFalse(self.push.userPromptedForNotifications);
}

/**
 * Test types are not set a second time when they are the same.
 */
- (void)testNotificationOptionsAuthorizedTwice {
    // SETUP
    self.push.authorizedNotificationSettings = UAAuthorizedNotificationSettingsAlert;

    // EXPECTATIONS
    [[self.mockRegistrationDelegate reject] notificationAuthorizedSettingsDidChange:UAAuthorizedNotificationSettingsAlert];

    // TEST
    self.push.authorizedNotificationSettings = UAAuthorizedNotificationSettingsAlert;

    // VERIFY
    XCTAssertNoThrow([self.mockRegistrationDelegate verify]);
    XCTAssertFalse(self.push.userPromptedForNotifications);
}

/**
 * Test registering a device token.
 */
- (void)testRegisteredDeviceToken {
    // SETUP
    [[[self.mockAppStateTracker stub] andReturnValue:@(UAApplicationStateBackground)] state];

    // Expect UAPush to update channel registration
    [[self.mockChannel expect] updateRegistration];

    NSData *token = [@"some-token" dataUsingEncoding:NSASCIIStringEncoding];

    // TEST
    [self.push application:self.mockApplication didRegisterForRemoteNotificationsWithDeviceToken:token];

    // VERIFY
    // Expect UAPush to receive the device token string
    // 736f6d652d746f6b656e = "some-token" in hex
    XCTAssertTrue([@"736f6d652d746f6b656e" isEqualToString:self.push.deviceToken]);

    XCTAssertNoThrow([self.mockChannel verify], @"should update channel registration");
}

-(void)testDidRegisterForRemoteNotificationsWithDeviceTokenDoesntRegisterChannelWhenInBackground {
    // SETUP
    [[[self.mockAppStateTracker stub] andReturnValue:@(UAApplicationStateBackground)] state];

    [[[self.mockChannel stub] andReturn:@"someChannelID"] identifier];

    // EXPECTATIONS
    [[self.mockChannel reject] updateRegistration];

    // TEST
    NSData *token = [@"some-token" dataUsingEncoding:NSASCIIStringEncoding];
    [self.push application:self.mockApplication didRegisterForRemoteNotificationsWithDeviceToken:token];

    // VERIFY
    // Expect UAPush to receive the device token string
    // 736f6d652d746f6b656e = "some-token" in hex
    XCTAssertTrue([@"736f6d652d746f6b656e" isEqualToString:self.push.deviceToken]);

    XCTAssertNoThrow([self.mockChannel verify], @"should not update channel registration");
}

-(void)testAuthorizedNotificationSettingsWhenPushNotificationsDisabled {
    // SETUP
    self.push.userPushNotificationsEnabled = NO;
    self.push.authorizedNotificationSettings = UAAuthorizedNotificationSettingsAlert;

    // TEST & VERIFY
    XCTAssert(self.push.authorizedNotificationSettings == UAAuthorizedNotificationSettingsAlert);
}

- (void)testEnablingDisabledPushUpdatesRegistration {
    // Setup
    [[self.mockChannel stub] andReturn:@"someChannelID"];
    self.push.componentEnabled = NO;

    // EXPECTATIONS
    __block NSMutableSet *expectedCategories = [NSMutableSet set];
    for (UANotificationCategory *category in self.push.combinedCategories) {
        [expectedCategories addObject:[category asUNNotificationCategory]];
    }
    [self expectUpdatePushRegistrationWithOptions:self.push.notificationOptions categories:expectedCategories];

    // Test
    self.push.componentEnabled = YES;

    // verify
    XCTAssertTrue(self.push.userPushNotificationsEnabled,
                  @"userPushNotificationsEnabled should be enabled when set to YES");
    XCTAssertTrue([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey],
                  @"userPushNotificationsEnabled should be stored in standardUserDefaults");
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should be called");
}

- (void)testEnablingDisabledPushDoesNotUpdateRegistrationWhenAppIsHandlingAuthorization {
    // Setup
    self.config.requestAuthorizationToUseNotifications = NO;

    [[self.mockChannel stub] andReturn:@"someChannelID"];
    self.push.componentEnabled = NO;

    // EXPECTATIONS
    [self rejectUpdatePushRegistrationWithOptions];

    // Test
    self.push.componentEnabled = YES;

    // verify
    XCTAssertTrue(self.push.userPushNotificationsEnabled,
                  @"userPushNotificationsEnabled should be enabled when set to YES");
    XCTAssertTrue([self.dataStore boolForKey:UAUserPushNotificationsEnabledKey],
                  @"userPushNotificationsEnabled should be stored in standardUserDefaults");
    XCTAssertNoThrow([self.mockPushRegistration verify], @"[UAAPNSRegistration updateRegistrationWithOptions:categories:completionHandler:] should not be called");
}

- (void)testUpdateAuthorizedNotificationTypesUpdatesChannelRegistrationWhenAppIsHandlingAuthorization {
    // SETUP
    self.config.requestAuthorizationToUseNotifications = NO;
    self.authorizedNotificationSettings = UAAuthorizedNotificationSettingsAlert | UAAuthorizedNotificationSettingsBadge;
    self.authorizationStatus = UAAuthorizationStatusAuthorized;

    // EXPECTATIONS
    XCTestExpectation *channelRegisterExpectation = [self expectationWithDescription:@"Called registerForcefully:NO"];
    [[[self.mockChannel expect] andDo:^(NSInvocation *invocation) {
        [channelRegisterExpectation fulfill];
    }] updateRegistration];

    // TEST
    [self.push updateAuthorizedNotificationTypes];

    // VERIFY
    [self waitForTestExpectations];
    XCTAssertNoThrow([self.mockChannel verify], @"updateRegistration should be called");
}

- (void)expectUpdatePushRegistrationWithOptions:(UANotificationOptions)expectedOptions categories:(NSSet<UANotificationCategory *> *)expectedCategories {
    [[[[self.mockPushRegistration expect] andDo:^(NSInvocation *invocation) {
        void *arg;
        [invocation getArgument:&arg atIndex:2];
        UANotificationOptions options = (UANotificationOptions)arg;
        XCTAssertTrue(expectedOptions == options);

        [invocation getArgument:&arg atIndex:4];
        void (^completionHandler)(BOOL) = (__bridge void(^)(BOOL))arg;

        if (completionHandler) {
            completionHandler(YES);
        }

        [self.mockRegistrationDelegate notificationRegistrationFinishedWithAuthorizedSettings:self.authorizedNotificationSettings categories:expectedCategories];
    }] ignoringNonObjectArgs] updateRegistrationWithOptions:0 categories:[OCMArg checkWithBlock:^BOOL(NSSet<UNNotificationCategory *> *categories) {
        return (expectedCategories.count == categories.count);
    }] completionHandler:OCMOCK_ANY];
}

- (void)rejectUpdatePushRegistrationWithOptions {
    [[[self.mockPushRegistration reject] ignoringNonObjectArgs] updateRegistrationWithOptions:0 categories:OCMOCK_ANY completionHandler:OCMOCK_ANY];
}

@end
