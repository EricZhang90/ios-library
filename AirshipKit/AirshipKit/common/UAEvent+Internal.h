/* Copyright Airship and Contributors */

#import "UAEvent.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Represents the possible priorities for an event.
 */
typedef NS_ENUM(NSInteger, UAEventPriority) {
    /**
     * Low priority event. When added in the background, it will not schedule a send
     * if the last send was within 15 mins. Adding in the foreground will schedule
     * sends normally.
     */
    UAEventPriorityLow,

    /**
     * Normal priority event. Sends will be scheduled based on the batching time.
     */
    UAEventPriorityNormal,

    /**
     * High priority event. A send will be scheduled immediately.
     */
    UAEventPriorityHigh
};

@interface UAEvent ()

///---------------------------------------------------------------------------------------
/// @name Event Internal Properties
///---------------------------------------------------------------------------------------

/**
 * The time the event was created.
 */
@property (nonatomic, copy) NSString *time;

/**
 * The unique event ID.
 */
@property (nonatomic, copy) NSString *eventID;

/**
 * The event's data.
 */
@property (nonatomic, strong) NSDictionary *data;

/**
 * The JSON event size in bytes.
 */
@property (nonatomic, readonly) NSUInteger jsonEventSize;

/**
 * The event's priority.
 */
@property (nonatomic, readonly) UAEventPriority priority;

///---------------------------------------------------------------------------------------
/// @name Event Internal Methods
///---------------------------------------------------------------------------------------

/**
 * Gets the current enabled notification types as a string array.
 *
 * @return The current notification types as a string array.
 */
- (NSArray *)notificationTypes;

/**
 * Gets the current notification authorization as a string.
 *
 * @return The current notification authorization as a string.
 */
- (NSString *)notificationAuthorization;


@end

NS_ASSUME_NONNULL_END
