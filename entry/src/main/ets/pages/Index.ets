import { media } from '@kit.MediaKit'
import MediaPlayer from '../utils/MediaPlayerUtils'
import { ProviderFeature } from '../viewmodel/ProviderManager'
import { avSession } from '@kit.AVSessionKit'
import MediaData from '../model/MediaData'

@Entry
@Component
struct Index {
  @State seekPosition: number = 0
  //点赞状态
  @State isLike:boolean = false
  //播放状态
  // @State playFlag:boolean = false
  //获取avPlay中的方法，控制音视频播放
  // private avPlayer:media.AVPlayer | undefined
  //播放状态 为什么不用上面那个而改成这个呢
  @StorageLink('isPlaying') isPlaying: boolean = false
  @StorageLink('currentPlayItem') currentPlayItem: avSession.AVQueueItem | null = null
  private providerManager: ProviderFeature | undefined
  //链接到ProviderFeature中管理的收藏状态Map
  @StorageLink('isFavorMap')isFavorMap:Map<String, boolean> = new Map<String, boolean>();
  @StorageLink("CurrentAVMetadata") currentAVMetadata?: avSession.AVMetadata = undefined
  @StorageLink("CurrentLoopMode") currentLoopMode: avSession.LoopMode = 0

  @State isProgressSliding: boolean = false
  private sliderTimer?: number


  //init方法中存在异步，所以把它放到生命周期执行
  async aboutToAppear() {
    // this.avPlayer = await MediaPlayer.instance.initial()
    this.providerManager = await ProviderFeature.getInstance()

    //准备好资源，让它进入准备状态
    // await MediaPlayer.instance.loadFromRawFile("test_44100_2.wav")

    await this.providerManager.init()
  }

  //当pageHide时，开启长时任务
  onPageHide(): void {
    this.providerManager?.startCountinuousTask()
  }

  aboutToDisappear(): void {
    this.providerManager?.unInit()
  }

  build() {
    Column() {
      //大图
      Image($rawfile('first_with_background.png'))
        .width('90%')
        .margin({ top: '25%', left: '5%' })
      //小标题1
      Text(this.currentPlayItem?.description?.title ? this.currentPlayItem?.description?.title : 'no Data')
        .font({ size: 26, weight: FontWeight.Bold, })
        .margin({ left: '7%', right: '7%' })
      //小标题2
      Text('first artist')
        .fontColor('#666')
        .margin({ left: '7%', top: 10, right: '7%' })
      //空白，给下面的挤下去
      Blank()
      //进度条
      Slider({
        //做进度条用的,先给个0
        value: 0,
        min: 0,
        max: 100,
        style: SliderStyle.OutSet
      })
        .trackThickness(5)
        .blockColor(Color.White)
        .selectedColor('#0A59F7')
        .showSteps(false)
        .showTips(false)
        .margin({ left: '4%', right: '4%' })
        .onChange((value: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.End) {
            this.providerManager?.seek(value)
          }
        })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Up) {
            this.sliderTimer = setTimeout(() => {
              this.isProgressSliding = false
            }, 200)
          } else {
            clearTimeout(this.sliderTimer)
            this.isProgressSliding = true
          }
        })
      //横向的容器中五个按钮
      Row() {
        Button({ stateEffect: true }) {
          Image(this.isFavorMap?.get(this.currentAVMetadata?.assetId) ?
            $r('app.media.ic_public_favor_filled') :
            $r('app.media.ic_public_favor'))
        }
        .width(30)
        .aspectRatio(1)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.providerManager!.toggleFavorite()
        })

        Button({ stateEffect: true }) {
          Image($r('app.media.ic_previous'))
        }
        .width(30)
        .aspectRatio(1)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          //这里要放个provideManager
          this.providerManager?.previous()
        })

        //播放按钮
        //做图标的三元运算，通过playFlag判断用哪个图标
        Button({ stateEffect: true }) {
          Image(this.isPlaying ? $r('app.media.ic_pause') : $r('app.media.ic_play'))
        }
        .width(54)
        .aspectRatio(1)
        .backgroundColor(Color.Transparent)
        //做播放/暂停逻辑
        .onClick(async () => {
        //   if (this.isPlaying) {
        //     await this.providerManager?.pause()
        //   } else {
        //     this.providerManager?.play()
        //   }
          this.providerManager?.playOrPause()
        })


        Button({ stateEffect: true }) {
          Image($r('app.media.ic_next'))
        }
        .width(30)
        .aspectRatio(1)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          //provideManager
          this.providerManager?.next()
        })

        Button({ stateEffect: true }) {
          Image(MediaData.loopModeList[this.currentLoopMode!])
        }
        .width(30)
        .aspectRatio(1)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.providerManager!.loopMode()
          console.log(`loop ${this.currentLoopMode}`)
        })
      }
      .margin({
        left: '7%',
        right: '7%',
        bottom: 25,
        top: 14
      })
      .width('86%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundImage($r('app.media.ic_background'))
    .backgroundImageSize(ImageSize.Cover)
  }
}