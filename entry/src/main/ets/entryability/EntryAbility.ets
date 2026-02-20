import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import MediaPlayer from '../utils/MediaPlayerUtils';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    let instance = MediaPlayer.getInstance()
    instance.context = this.context
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage) {
    // 1.Get the main window of the application.
    let windowClass: window.Window | undefined = undefined;
    windowStage.getMainWindow().then(windowClass => {
      console.info('Succeeded in obtaining the main window. Data: ' + JSON.stringify(windowClass));
      // 2.Set the window to full screen to achieve immersive effects.
      windowClass.setWindowLayoutFullScreen(true).then(() => {
        console.info('Succeeded in setting the window layout to full-screen mode.');
      }).catch((e: BusinessError) => {
        console.error('Failed to set the window layout to full-screen mode. Cause:' + JSON.stringify(e));
      })
    }).catch((err: BusinessError) => {
      console.error('Failed to obtain the main window. Cause: ' + JSON.stringify(err));
    })
    // 3.Load the corresponding target page for the immersive window.
    windowStage.loadContent("pages/Index", (err) => {
      if (err.code) {
        console.error('Failed to load the content. Cause:' + JSON.stringify(err));
        return;
      }
      console.info('Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}