/* Copyright Airship and Contributors */

@import AirshipKit;
#import "HomeViewController.h"

@interface HomeViewController ()

@end

@implementation HomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(refreshView)
                                                 name:UAChannelUpdatedEvent
                                               object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self refreshView];
}

- (IBAction)buttonTapped:(id)sender {
    if (sender == self.enablePushButton) {
        [UAirship push].userPushNotificationsEnabled = YES;
    }

    if (sender == self.channelIDButton && [UAirship channel].identifier) {
        [UIPasteboard generalPasteboard].string = [UAirship channel].identifier;

        UIAlertController* alert = [UIAlertController alertControllerWithTitle:nil
                                                                       message:NSLocalizedStringFromTable(@"UA_Copied_To_Clipboard", @"UAPushUI", @"Copied to clipboard string")
                                                                preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedStringFromTable(@"UA_OK", @"UAPushUI", @"OK button string")
                                                           style:UIAlertActionStyleDefault
                                                         handler:^(UIAlertAction * _Nonnull action) {
                                                             [self dismissViewControllerAnimated:YES completion:nil];
                                                         }];

        [alert addAction:okAction];

        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)refreshView {
    if ([UAirship push].userPushNotificationsEnabled) {
        [self.channelIDButton setTitle:[UAirship channel].identifier forState:UIControlStateNormal];
        self.channelIDButton.hidden = NO;
        self.enablePushButton.hidden = YES;
        return;
    }
    self.channelIDButton.hidden = YES;
    self.enablePushButton.hidden = NO;
}

@end
