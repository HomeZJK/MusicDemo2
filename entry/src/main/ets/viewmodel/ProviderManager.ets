import MediaData from "../model/MediaData"
import { media } from "@kit.MediaKit"
import MediaPlayer, { AVPlayerState } from "../utils/MediaPlayerUtils"
import { avSession } from "@kit.AVSessionKit"
import { wantAgent,common} from "@kit.AbilityKit"
import backgroundTaskManager from "@ohos.resourceschedule.backgroundTaskManager"
import MediaPlayerUtils from "../utils/MediaPlayerUtils"

/**
 * AVMetadata 就是向系统和用户展示“现在正在播放什么”的详细信息集，是 AVSession 与系统 UI（锁屏、通知栏等）进行信息交互的核心数据载体。
 */
export class ProviderFeature {
  // private static providerSelf: ProviderFeature | undefined
  //使用饿汉式单例，直接创建实例
  public static instance:ProviderFeature = new ProviderFeature()

  //使用MediaPlayer的饿汉式单例实例
  private mediaPlayer:MediaPlayer = MediaPlayer.instance //重命名以明确其来源
  private mediaData:MediaData = new MediaData()
  private avPlayer?:media.AVPlayer = undefined  //储存AVPlayer实例
  private session?:avSession.AVSession = undefined
  private currentTime:number = 0

  //AVSession播放状态
  private currentState:avSession.AVPlaybackState = {
    state:avSession.PlaybackState.PLAYBACK_STATE_PREPARE
  }

  //—————— AppStorage 链接的属性
  //播放状态
  private isPlaying:SubscribedAbstractProperty<boolean> = AppStorage.setAndLink("IsPlaying", false)
  //当前播放项
  private currentPlayItem: SubscribedAbstractProperty<avSession.AVQueueItem> =
    AppStorage.setAndLink('currentPlayItem', {} as avSession.AVQueueItem)
  //播放进度


  //当前AVSession元数据
  private currentAVMetadata:SubscribedAbstractProperty<avSession.AVMetadata> = AppStorage.setAndLink<avSession.AVMetadata>("CurrentAVMetadata", {} as avSession.AVMetadata)

  //当前循环模式



  //收藏状态
  private isFavorMap: SubscribedAbstractProperty<Map<String, boolean>> =
    AppStorage.setAndLink<Map<String, boolean>>("IsFavorMap", new Map())


  //私有构造函数，防止外部直接new
  private constructor() {
  }

  /**
   * 初始化资源和会话
   * @param context
   * @returns
   */
  async init(context:common.UIAbilityContext): Promise<void> { //添加context参数


    //1.设置MediaPlayer上下文
    this.mediaPlayer.setContext(context)
    //2.初始化MediaPlayer 内部的 AVPlayer
    this.avPlayer = await this.mediaPlayer.init()
    if (!this.avPlayer) {
      console.error("ProviderFeature: Failed to initialize MediaPlayer's AVPlayer.")
      return  //初始化失败，提前退出
    }
    //3.注册MediaPlayer的监听器
    this.registerAVSessionListener()
    //4.创建AVSession并激活
    await this.getAVSession(context) //传递context
    //5.初始化AppStorage数据
    const initialMap:Map<String, boolean> = new Map()
    initialMap.set(this.mediaData.avMetadataList[0].assetId, false)
      .set(this.mediaData.avMetadataList[1].assetId, false)
      .set(this.mediaData.avMetadataList[2].assetId, false)
    this.isFavorMap.set(initialMap)

    this.currentAVMetadata.set(this.mediaData.avMetadataList[0])
    this.currentPlayItem.set(this.mediaData.queueItems[0])
    //6.设置初始播放状态
    this.session?.setAVPlaybackState(this.currentState, () => {})
    //7.初始化元数据
    await this.setAVMetadataToController(0)
    //8.加载初始媒体文件
    await this.mediaPlayer.loadFromRawFile("test_44100_2.wav")
  }

  /**
   * 销毁
   * @returns
   */
  async unInit(): Promise<void> {
    await this.UnRegisterListener()
    if (this.avPlayer) {
      await this.UnRegisterListener()
      this.avPlayer.release(() => {

      })
    }
  }

  /**
   * 设置AVSession元数据
   * @param itemId
   */
  async setAVMetadataToController(itemId: number) {
    let avMetadata: avSession.AVMetadata = this.mediaData.avMetadataList[itemId]
    this.session?.setAVMetadata(avMetadata, () => {
    })
  }

  /**
   * 创建并激活AVSession
   * @param context
   * @returns
   */
  async getAVSession(context:common.UIAbilityContext):Promise<boolean>{
    let ret:boolean = true
    if (!this.session) {
      console.warn("AVSession already exists.")
      return ret
    }
    try {
      this.session = await avSession.createAVSession(context, "MusicPlayerDemo", "audio") //使用传入的context
      this.registerAVSessionListener()
      await this.session.activate()
    }catch (error) {
      console.error("Failed to create or activate AVSession", error)
      ret = false
    }
    return ret
  }

  /**
   * 注册AVSession监听器
   */
  async registerAVSessionListener() {
    try {
      this.session?.on("play", async () => {
        this.avPlayer?.play(() => {
        })
        this.isPlaying.set(true)
        this.currentState = {
          state: avSession.PlaybackState.PLAYBACK_STATE_PLAY,
          position: {
            elapsedTime: this.currentTime,
            updateTime: new Date().getTime()
          }
        }
        this.session?.setAVPlaybackState(this.currentState, () => {
        })
      })

      this.session?.on("pause", async () => {
        this.avPlayer?.pause(() => {
          this.isPlaying.set(false)
          this.currentState = {
            state: avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
            position: {
              elapsedTime: this.currentTime,
              updateTime: new Date().getTime()
            }
          }
          this.session?.setAVPlaybackState(this.currentState, () => {
          })
        })
      })
      this.session?.on("stop", async () => {
        this.avPlayer?.stop(() => {
        })
        this.isPlaying.set(false)
        this.currentState = {
          state: avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
          position: {
            elapsedTime: this.currentTime,
            updateTime: new Date().getTime()
          }
        }
        this.session?.setAVPlaybackState(this.currentState, () => {
        })
      })

      this.session?.on("playPrevious", async () => {
        await this.previous()
      })

      this.session?.on("playNext", async () => {
        await this.next()
      })

      this.session?.on("toggleFavorite", async (assetId) => {
        this.isFavorMap!.get().set(assetId, !this.isFavorMap.get().get(assetId))
        this.currentState.isFavorite = this.isFavorMap.get().get(assetId)
        this.session?.setAVPlaybackState(this.currentState, () => {
        })
      })

      this.session?.on("setLoopMode", async (mode) => {

      })

      this.session?.on("seek", async (position) => {
        if (position >= this.currentAVMetadata.get().duration!) {
          this.next()
        } else {
          this.avPlayer?.seek(position)
          this.currentState = {
            state: this.isPlaying.get() ? avSession.PlaybackState.PLAYBACK_STATE_PLAY :
              avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
            position: {
              elapsedTime: position,
              updateTime: new Date().getTime()
            }
          }
          this.session?.setAVPlaybackState(this.currentState, () => {
          })
        }
      })

    } catch (error) {
    }
  }

  async UnRegisterListener(): Promise<void> {
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
  async setAVMetadataController(itemId: number): Promise<void> {
    let avMetadata: avSession.AVMetadata = this.mediaData.avMetadataList[itemId]
    await this.session?.setAVMetadata(avMetadata)
  }

  // //创建AVSession实例，该方法表示是否创建成功的boolean，如果创建成功，就可以直接在session字段中调用
  // async CreateAVSession(): Promise<boolean> {
  //   let ret: boolean = true
  //   if (this.session) {
  //     return ret
  //   }
  //   //这里要进行'!'非空断言
  //   this.session = await avSession.createAVSession(MediaPlayer.instance.context!, 'AVSessionDemo', 'audio')
  //   this.RegisterSessionListener()
  //   //这里要加给BusinessError加泛型<number>不然会报错
  //   await this.session.activate().catch((err: BusinessError<number>) => {
  //     if (err) {
  //       ret = false
  //     }
  //   })
  //   return ret
  // }

  // //注册监听
  // async RegisterSessionListener(): Promise<void> {
  //   this.session?.on('play', async () => {
  //     this.avPlayer?.play()
  //     this.isPlaying.set(true)
  //     this.currentState = {
  //       state: avSession.PlaybackState.PLAYBACK_STATE_PLAY,
  //       position: {
  //         elapsedTime: this.currentTime,
  //         updateTime: new Date().getTime()
  //       }
  //     }
  //     await this.session?.setAVPlaybackState(this.currentState)
  //   })
  //   this.session?.on('pause', async () => {
  //     this.avPlayer?.pause()
  //     this.isPlaying.set(false)
  //     this.currentState = {
  //       state: avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
  //       position: {
  //         elapsedTime: this.currentTime,
  //         updateTime: new Date().getTime()
  //       }
  //     }
  //     await this.session?.setAVPlaybackState(this.currentState)
  //   })
  //   this.session?.on('stop', async () => {
  //     this.avPlayer?.stop()
  //     this.isPlaying.set(false)
  //     this.currentState.state = avSession.PlaybackState.PLAYBACK_STATE_PAUSE
  //     await this.session?.setAVPlaybackState(this.currentState)
  //   })
  //   this.session?.on('playNext', async () => {
  //     let nextId: number = this.currentPlayItem.get().itemId + 1
  //     nextId = this.mediaData.queueInfoList.length > nextId ? nextId : 0
  //     this.currentPlayItem.set(this.mediaData.queueInfoList[nextId])
  //     await this.setAVMetadataController(nextId)
  //     await MediaPlayer.instance.loadFromRawFile('test_44100_2.wav')
  //     MediaPlayer.instance.onCallback('prepared', async () => {
  //       // this.localPlayOrPause()
  //       //这里为什么要加await，之前不加也行啊,加了也没啥不一样
  //       //这里加了await后，应用-后台任务-播控中心的ui同步了
  //       await this.localPlayOrPause()
  //       this.currentState = {
  //         state: this.isPlaying.get() ? avSession.PlaybackState.PLAYBACK_STATE_PLAY :
  //           avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
  //         position: {
  //           elapsedTime: this.currentTime,
  //           updateTime: new Date().getTime()
  //         }
  //       }
  //       await this.session?.setAVPlaybackState(this.currentState)
  //     })
  //   })
  //   this.session?.on('playPrevious', async () => {
  //     let previousId: number = this.currentPlayItem?.get().itemId as number - 1
  //     previousId = previousId < 0 ? this.mediaData.queueInfoList.length - 1 : previousId
  //
  //     this.currentPlayItem.set(this.mediaData.queueInfoList[previousId])
  //     await this.setAVMetadataController(previousId)
  //     //正常情况下，我肯应用根据currentPlayItem中记录的资源文件重新设置是播放歌曲，但是我们只有一个资源文件，就循环播放
  //     await MediaPlayer.instance.loadFromRawFile('test_44100_2.wav')
  //     MediaPlayer.instance.onCallback('prepared', async () => {
  //       // this.localPlayOrPause()
  //       //这里为什么要加await，之前不加也行啊,加了也没啥不一样
  //       //这里加了await后，应用-后台任务-播控中心的ui同步了
  //       await this.localPlayOrPause()
  //       this.currentState = {
  //         state: this.isPlaying.get() ? avSession.PlaybackState.PLAYBACK_STATE_PLAY :
  //           avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
  //         position: {
  //           elapsedTime: this.currentTime,
  //           updateTime: new Date().getTime()
  //         }
  //       }
  //       console.log(this.isPlaying.get() + '')
  //       await this.session?.setAVPlaybackState(this.currentState)
  //     })
  //   })
  // }

  //单独封装一个播放和暂停的方法，用于在提供方单独点击播放和暂停时可以把播放状态同步给控制方
  async play(): Promise<void> {
    this.localPlayOrPause()
    this.currentState = {
      state: this.isPlaying.get() ? avSession.PlaybackState.PLAYBACK_STATE_PLAY :
        avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
      position: {
        elapsedTime: this.currentTime,
        updateTime: new Date().getTime()
      }
    }
    await this.session?.setAVPlaybackState(this.currentState)
  }

  async pause(): Promise<void> {
    this.localPlayOrPause()
    this.currentState = {
      state: this.isPlaying.get() ? avSession.PlaybackState.PLAYBACK_STATE_PLAY :
        avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
      position: {
        elapsedTime: this.currentTime,
        updateTime: new Date().getTime()
      }
    }
    await this.session?.setAVPlaybackState(this.currentState)
  }

  //开始长时任务
  async startCountinuousTask(): Promise<void> {
    let wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: 'com.example.musicplayerdemo',
          abilityName: 'EntryAbility'
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    }
    let tmpWantAgent = wantAgent.getWantAgent(wantAgentInfo)
    this.session?.setLaunchAbility(tmpWantAgent)
    backgroundTaskManager.startBackgroundRunning(MediaPlayer.instance.context,
      backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK, tmpWantAgent)
  }

  //关闭长时任务
  async stopContinuousTask(): Promise<boolean> {
    return new Promise((resolve) => {
      backgroundTaskManager.stopBackgroundRunning(MediaPlayer.instance.context, (err, _) => {
        if (err) {
          resolve(false)
        } else {
          resolve(true)
        }
      })
    })
  }
}