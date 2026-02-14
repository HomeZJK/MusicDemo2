import MediaData from "../model/MediaData"
import { media } from "@kit.MediaKit"
import MediaPlayer, { AVPlayerState } from "../utils/MediaPlayerUtils"
import { avSession } from "@kit.AVSessionKit"
import { wantAgent } from "@kit.AbilityKit"
import backgroundTaskManager from "@ohos.resourceschedule.backgroundTaskManager"

//测试更新代码
//测试1.0.2
/**
 * AVMetadata 就是向系统和用户展示“现在正在播放什么”的详细信息集，是 AVSession 与系统 UI（锁屏、通知栏等）进行信息交互的核心数据载体。
 */
export class ProviderFeature {
  private static providerSelf: ProviderFeature | undefined
  private mediaData: MediaData = new MediaData()
  private avPlayer: media.AVPlayer | undefined
  private session?:avSession.AVSession
  private currentState:avSession.AVPlaybackState = {
    state:avSession.PlaybackState.PLAYBACK_STATE_PAUSE
  }
  private currentTime:number = 0

  //为什么不用avSession
  // private currentPlayItem:avSession.AVQueueItem | undefined

  //为啥要这么写，写一大串看又看不懂
  private currentPlayItem: SubscribedAbstractProperty<avSession.AVQueueItem> =
    AppStorage.setAndLink('currentPlayItem', {} as avSession.AVQueueItem)
  //好像懂一点点了，可能跟状态变量有点关系
  private isPlaying: SubscribedAbstractProperty<boolean> = AppStorage.setAndLink('isPlaying', false)

  //收藏点赞功能需要的字段
  //创建一个Map来存储<assetId, isFavorite>的映射，并链接到AppStorage
  private isFavorMap:SubscribedAbstractProperty<Map<string, boolean>> = AppStorage.setAndLink<Map<string, boolean>>('isFavorMap', new Map<string , boolean>())

  //单例模式
  static async getInstance(): Promise<ProviderFeature> {
    if (!ProviderFeature.providerSelf) {
      ProviderFeature.providerSelf = new ProviderFeature()
    }
    return ProviderFeature.providerSelf
  }

  //初始化资源
  async init(): Promise<void> {
    this.avPlayer = await MediaPlayer.instance.initial()
    await MediaPlayer.instance.loadFromRawFile('test_44100_2.wav')
    //因为上面写了那么一大串，所以现在不这么写，要跟上面产生关系
    // this.currentPlayItem = this.mediaData.queueInfoList[0]
    this.currentPlayItem.set(this.mediaData.queueInfoList[0])
    await this.CreateAVSession()
    //同步播放后台和元数据
    this.isPlaying.set(false)
    this.currentState.state = avSession.PlaybackState.PLAYBACK_STATE_PAUSE
    await this.session?.setAVPlaybackState(this.currentState)
    await this.setAVMetadataController(0)


  }

  async unInit():Promise<void>{
    this.UnRegisterListener()
    if (this.avPlayer) {
      this.avPlayer.release()
    }
  }

  async UnRegisterListener():Promise<void>{
    if (this.session) {
      this.session.off('play')
      this.session.off('pause')
      this.session.off('stop')
      this.session.off('playNext')
      this.session.off('playPrevious')
    }

    //销毁已创建的会话
    this.session?.destroy((err) => {

    })
  }

  //播放与暂停控制方法
  async localPlayOrPause(): Promise<void> {
    if (!this.avPlayer) {
      return
    }
    if (this.avPlayer.state === AVPlayerState.PLAYING) {
      await this.avPlayer.pause()
      this.isPlaying.set(false)
    } else if (this.avPlayer.state === AVPlayerState.STOPPED) {
      await this.avPlayer.prepare()
      await this.avPlayer.play()
      this.isPlaying.set(true)
    } else {
      await this.avPlayer.play()
      this.isPlaying.set(true)
    }
  }

  //上一首
  async previous(): Promise<void> {
    // let previousId:number = this.currentPlayItem?.itemId as number - 1

    //好好的itemId，为什么变成了get().itemId
    let previousId: number = this.currentPlayItem?.get().itemId as number - 1
    previousId = previousId < 0 ? this.mediaData.queueInfoList.length - 1 : previousId

    // this.currentPlayItem = this.mediaData.queueItemDescFirst[previousId]
    //这里为什么又用set()了
    this.currentPlayItem.set(this.mediaData.queueInfoList[previousId])

    //正常情况下，我肯应用根据currentPlayItem中记录的资源文件重新设置是播放歌曲，但是我们只有一个资源文件，就循环播放
    await MediaPlayer.instance.loadFromRawFile('test_44100_2.wav')
    MediaPlayer.instance.onCallback('prepared', () => {
      this.localPlayOrPause()
    })

  }

  //下一首
  async next(): Promise<void> {
    // let  nextId:number = this.currentPlayItem?.itemId as number + 1
    let nextId: number = this.currentPlayItem.get().itemId as number + 1

    nextId = this.mediaData.queueInfoList.length > nextId ? nextId : 0
    // this.currentPlayItem = this.mediaData.queueInfoList[nextId]
    this.currentPlayItem.set(this.mediaData.queueInfoList[nextId])

    //复制粘贴了上面的代码
    await MediaPlayer.instance.loadFromRawFile('test_44100_2.wav')
    MediaPlayer.instance.onCallback('prepared', () => {
      this.localPlayOrPause()
    })
  }

  //播放模式
  loopMode() {

  }

  //喜欢
  toggleFavorite() {

  }

  //从数据源中通过itemId获取当前正在播放的AVMetadata并设置给对话
  async setAVMetadataController(itemId:number):Promise<void>{
    let avMetadata:avSession.AVMetadata = this.mediaData.avMetadataList[itemId]
    await this.session?.setAVMetadata(avMetadata)
  }

  //创建AVSession实例，该方法表示是否创建成功的boolean，如果创建成功，就可以直接在session字段中调用
  async CreateAVSession():Promise<boolean>{
    let  ret:boolean = true
    if (this.session) {
      return ret
    }
    //这里要进行'!'非空断言
    this.session = await avSession.createAVSession(MediaPlayer.instance.context!, 'AVSessionDemo','audio')
    this.RegisterSessionListener()
    //这里要加给BusinessError加泛型<number>不然会报错
    await this.session.activate().catch((err:BusinessError<number>) => {
      if (err) {
        ret = false
      }
    })
    return ret
  }

  //注册监听
  async RegisterSessionListener():Promise<void>{
    this.session?.on('play',async  () => {
      this.avPlayer?.play()
      this.isPlaying.set(true)
      this.currentState = {
        state:avSession.PlaybackState.PLAYBACK_STATE_PLAY,
        position:{
          elapsedTime:this.currentTime,
          updateTime: new Date().getTime()
        }
      }
      await this.session?.setAVPlaybackState(this.currentState)
    })
    this.session?.on('pause',async () => {
      this.avPlayer?.pause()
      this.isPlaying.set(false)
      this.currentState = {
        state:avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        position:{
          elapsedTime:this.currentTime,
          updateTime: new Date().getTime()
        }
      }
      await this.session?.setAVPlaybackState(this.currentState)
    })
    this.session?.on('stop',async () => {
      this.avPlayer?.stop()
      this.isPlaying.set(false)
      this.currentState.state = avSession.PlaybackState.PLAYBACK_STATE_PAUSE
      await this.session?.setAVPlaybackState(this.currentState)
    })
    this.session?.on('playNext', async () => {
      let nextId:number = this.currentPlayItem.get().itemId + 1
      nextId = this.mediaData.queueInfoList.length > nextId ? nextId : 0
      this.currentPlayItem.set(this.mediaData.queueInfoList[nextId])
      await this.setAVMetadataController(nextId)
      await MediaPlayer.instance.loadFromRawFile('test_44100_2.wav')
      MediaPlayer.instance.onCallback('prepared',async () => {
        // this.localPlayOrPause()
        //这里为什么要加await，之前不加也行啊,加了也没啥不一样
        //这里加了await后，应用-后台任务-播控中心的ui同步了
        await this.localPlayOrPause()
        this.currentState = {
          state:this.isPlaying.get() ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
          position:{
            elapsedTime:this.currentTime,
            updateTime:new Date().getTime()
          }
        }
        await this.session?.setAVPlaybackState(this.currentState)
      })
    })
    this.session?.on('playPrevious',async () => {
      let previousId: number = this.currentPlayItem?.get().itemId as number - 1
      previousId = previousId < 0 ? this.mediaData.queueInfoList.length - 1 : previousId

      this.currentPlayItem.set(this.mediaData.queueInfoList[previousId])
      await this.setAVMetadataController(previousId)
      //正常情况下，我肯应用根据currentPlayItem中记录的资源文件重新设置是播放歌曲，但是我们只有一个资源文件，就循环播放
      await MediaPlayer.instance.loadFromRawFile('test_44100_2.wav')
      MediaPlayer.instance.onCallback('prepared', async () => {
        // this.localPlayOrPause()
        //这里为什么要加await，之前不加也行啊,加了也没啥不一样
        //这里加了await后，应用-后台任务-播控中心的ui同步了
        await this.localPlayOrPause()
        this.currentState = {
          state:this.isPlaying.get() ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
          position:{
            elapsedTime:this.currentTime,
            updateTime:new Date().getTime()
          }
        }
        console.log(this.isPlaying.get() + '')
        await this.session?.setAVPlaybackState(this.currentState)
      })
      })
  }

  //单独封装一个播放和暂停的方法，用于在提供方单独点击播放和暂停时可以把播放状态同步给控制方
  async play():Promise<void>{
    this.localPlayOrPause()
    this.currentState = {
      state:this.isPlaying.get() ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
      position:{
        elapsedTime:this.currentTime,
        updateTime:new Date().getTime()
      }
    }
    await this.session?.setAVPlaybackState(this.currentState)
  }

  async pause():Promise<void>{
    this.localPlayOrPause()
    this.currentState = {
      state:this.isPlaying.get() ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
      position:{
        elapsedTime:this.currentTime,
        updateTime:new Date().getTime()
      }
    }
    await this.session?.setAVPlaybackState(this.currentState)
  }

  //开始长时任务
  async startCountinuousTask():Promise<void>{
    let wantAgentInfo:wantAgent.WantAgentInfo = {
      wants:[
        {
          bundleName:'com.example.musicplayerdemo',
          abilityName:'EntryAbility'
        }
      ],
      actionType:wantAgent.OperationType.START_ABILITY,
      requestCode:0,
      actionFlags:[wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    }
    let tmpWantAgent =  wantAgent.getWantAgent(wantAgentInfo)
    this.session?.setLaunchAbility(tmpWantAgent)
    backgroundTaskManager.startBackgroundRunning(MediaPlayer.instance.context,backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, tmpWantAgent)
  }

  //关闭长时任务
  async stopContinuousTask():Promise<boolean>{
    return new Promise((resolve) => {
      backgroundTaskManager.stopBackgroundRunning(MediaPlayer.instance.context,(err,_) => {
        if (err) {
          resolve(false)
        }else {
          resolve(true)
        }
      })
    })
  }

}