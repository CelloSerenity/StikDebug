/* 
    Copyright (C) 2025  Serge Alagon

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>. 
*/

#import <objc/runtime.h>
#import "FloatingButtonWindow.h"
#import "PrivateHeaders.h"

static BOOL isImmortalized;

static void prefsChanged() {
    isImmortalized = [[NSUserDefaults standardUserDefaults] boolForKey:@"immortalized"];
}

static void (*original_sceneID_updateWithSettingsDiff_transitionContext_completion)(id, SEL, id, id, id, id);

/* thanks to @khanhduytran0 for this wonderful hook. goat */
void new_sceneID_updateWithSettingsDiff_transitionContext_completion(id self, SEL _cmd, id arg1, id arg2, id arg3, id arg4) {
    if (!isImmortalized) {
        return original_sceneID_updateWithSettingsDiff_transitionContext_completion(self, _cmd, arg1, arg2, arg3, arg4);
    }

    /* universal approach using description. hehe lazy */

    NSString *diffDescription = [arg2 description];


 if ([diffDescription containsString:@"foreground = NotSet"] || 
       [diffDescription containsString:@"foreground = No"] || 
     [diffDescription containsString:@"foreground = BSSettingFlagNo"] || 
     [diffDescription containsString:@"foreground = NO"]) { 
    return;
   }

    if ([diffDescription containsString:@"hostContextIdentifierForSnapshotting = 0"] || 
      [diffDescription containsString:@"scenePresenterRenderIdentifierForSnapshotting = 0"] ||
    [diffDescription containsString:@"targetOfEventDeferringEnvironments = (empty)"]) { 
      return;
   }
    
  if ([diffDescription containsString:@"FBSceneSnapshotAction:"]) { 
     return;
  }

/*   BOOL isGoingToForeground = [diffDescription containsString:@"foreground = Yes"] || 
                            [diffDescription containsString:@"foreground = YES"] || 
                                [diffDescription containsString:@"foreground = BSSettingFlagYes"];

    if (!isGoingToForeground) {
        if ([diffDescription containsString:@"deactivationReasons = systemGesture"] ||
            [diffDescription containsString:@"deactivationReasons = systemAnimation"] ||
           [diffDescription containsString:@"systemGesture, systemAnimation"]) {
            return;
        }
    }
*/
    return original_sceneID_updateWithSettingsDiff_transitionContext_completion(self, _cmd, arg1, arg2, arg3, arg4);
}

static void setup() {
    dispatch_async(dispatch_get_main_queue(), ^{
        Class targetClass = objc_getClass("FBSWorkspaceScenesClient");
        SEL originalSelector = @selector(sceneID:updateWithSettingsDiff:transitionContext:completion:);
        Method originalMethod = class_getInstanceMethod(targetClass, originalSelector);

        if (originalMethod) {
            original_sceneID_updateWithSettingsDiff_transitionContext_completion = (void (*)(id, SEL, id, id, id, id))method_getImplementation(originalMethod);
            method_setImplementation(originalMethod, (IMP)new_sceneID_updateWithSettingsDiff_transitionContext_completion);
        }

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)prefsChanged, CFSTR("com.sergy.immortalizerjailed.updateprefs"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        [[FloatingButtonWindow sharedInstance] showButton];
    });
}

__attribute__((constructor)) static void initialize() {
	prefsChanged();
    setup();
}
