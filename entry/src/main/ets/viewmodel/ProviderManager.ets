import MediaData from "../model/MediaData"
import { media } from "@kit.MediaKit"
import MediaPlayer, { AVPlayerState } from "../utils/MediaPlayerUtils"
import { avSession } from "@kit.AVSessionKit"
import { wantAgent } from "@kit.AbilityKit"
import backgroundTaskManager from "@ohos.resourceschedule.backgroundTaskManager"

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

  //AVSession元数据
  private currentAVMetadata: SubscribedAbstractProperty<avSession.AVMetadata> =
    AppStorage.setAndLink<avSession.AVMetadata>("CurrentAVMetadata", {} as avSession.AVMetadata)
  //当前播放项
  private currentPlayItem: SubscribedAbstractProperty<avSession.AVQueueItem> =
    AppStorage.setAndLink('currentPlayItem', {} as avSession.AVQueueItem)
  private isPlaying: SubscribedAbstractProperty<boolean> = AppStorage.setAndLink('isPlaying', false)

  //收藏点赞功能需要的字段
  //创建一个Map来存储<assetId, isFavorite>的映射，并链接到AppStorage
  private isFavorMap:SubscribedAbstractProperty<Map<String, boolean>> = AppStorage.setAndLink<Map<String, boolean>>('isFavorMap', new Map<String , boolean>())

  // 循环模式
  private currentLoopModel: SubscribedAbstractProperty<avSession.LoopMode> =
    AppStorage.setAndLink("CurrentLoopMode", avSession.LoopMode.LOOP_MODE_SEQUENCE)



  //单例模式
  static async getInstance(): Promise<ProviderFeature> {
    if (!ProviderFeature.providerSelf) {
      ProviderFeature.providerSelf = new ProviderFeature()
    }
    return ProviderFeature.providerSelf
  }

  //初始化资源
  async init(): Promise<void> {
    //同步播放后台和元数据
    /*
        这几行代码共同完成了AVSession的首次状态同步
        * 创建了会话（CreateAVSession）
        * 同步了内部ui状态（isPlaying.set(false)）
        * 同步了系统播放状态（setAVPlaybackState）
        * 同步了系统元数据（setAVMetadataController）
        * 这确保了应用启动时，无论是你的应用 UI 还是系统的锁屏/通知栏 UI，都对当前的播放情况（有一首歌待播放，但尚未开始）有一致的认识。这是实现无缝媒体体验的基础。
     */
    this.avPlayer = await MediaPlayer.instance.initial()
    this.RegisterSessionListener()
    await this.CreateAVSession()  //创建并激活AVSession实例
    const map: Map<String, boolean> = new Map()
    map.set(this.mediaData.avMetadataList[0].assetId, false)
      .set(this.mediaData.avMetadataList[1].assetId, false)
      .set(this.mediaData.avMetadataList[2].assetId, false)
    this.isFavorMap.set(map)

    //初始化元数据
    this.currentAVMetadata.set(this.mediaData.avMetadataList[0])
    //初始化播放项
    this.currentPlayItem.set(this.mediaData.queueInfoList[0])
    //将this.currentState中的对象推送给AVSession。最关键的一步
    this.session?.setAVPlaybackState(this.currentState, () => {})
    //设置AVSession的元数据（AVMetadata），包括当前播放的歌曲名称，艺术家，封面图片，时常，收藏状态等。非常重要的一步
    await this.setAVMetadataToController(0)
    await MediaPlayer.instance.loadFromRawFile('test_44100_2.wav')
  }

  async unInit():Promise<void>{
    this.UnRegisterListener()
    if (this.avPlayer) {
      this.avPlayer.release()
    }
  }

  // 设置AVSession元数据
  async setAVMetadataToController(itemId: number) {
    let avMetadata: avSession.AVMetadata = this.mediaData.avMetadataList[itemId]
    this.session?.setAVMetadata(avMetadata, () => {
    })
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
      this.session?.setAVPlaybackState(this.currentState, () => {})
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
      this.session?.setAVPlaybackState(this.currentState, () => {})
    })
    this.session?.on('stop',async () => {
      this.avPlayer?.stop(() => {})
      this.isPlaying.set(false)
      this.currentState = {
        state: avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        position: {
          elapsedTime: this.currentTime,
          updateTime: new Date().getTime()
        }
      }
      this.session?.setAVPlaybackState(this.currentState, () => {})
    })
    this.session?.on('playNext', async () => {
      await this.next()
    })
    this.session?.on('playPrevious',async () => {
      await this.previous()
    })

    //————监听来自系统UI的toggleFavorite指令———— 后台收藏状态同步
    this.session?.on('toggleFavorite', (assetId:string) => {
      this.isFavorMap!.get().set(assetId, !this.isFavorMap.get().get(assetId))
      this.currentState.isFavorite = this.isFavorMap.get().get(assetId)
      this.session?.setAVPlaybackState(this.currentState, () => {
      })
    })

    this.session?.on("setLoopMode", async (mode) => {
      await this.loopMode()
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
  }

  async UnRegisterListener():Promise<void>{
    if (this.session) {
      this.session.off('play')
      this.session.off('pause')
      this.session.off('stop')
      this.session.off('playNext')
      this.session.off('playPrevious')
      this.session.off("toggleFavorite")
      this.session.off("setLoopMode")
      this.session.off("seek")
    }
    //销毁已创建的会话
    this.session?.destroy((err) => {
    })
  }

  //播放与暂停控制方法
  async localPlayOrPause() {
    if (!this.avPlayer) {
      return
    }
    if (this.avPlayer?.state === AVPlayerState.PLAYING) {
      this.avPlayer.pause(() => {
      })
      this.isPlaying.set(false)
    } else if (this.avPlayer?.state === AVPlayerState.PAUSED) {
      this.avPlayer.play(() => {
      })
      this.isPlaying.set(true)
    } else if (this.avPlayer?.state === AVPlayerState.STOPPED) {
      this.avPlayer.prepare(() => {
      })
      this.avPlayer.play(() => {
      })
      this.isPlaying.set(true)
    } else {
      this.avPlayer?.play(() => {
      })
      this.isPlaying.set(true)
    }
  }

  //上一首
  async previous(): Promise<void> {
    let previousId = this.currentPlayItem.get().itemId - 1
    previousId = previousId < 0 ? previousId + this.mediaData.queueItems.length : previousId
    await this.switchNewItem(previousId)
  }

  //下一首
  async next(): Promise<void> {
    let nextId = this.currentPlayItem.get().itemId + 1
    nextId = nextId % this.mediaData.queueItems.length
    await this.switchNewItem(nextId)
  }

  // 切换播放状态
  async switchNewItem(itemId: number) {
    await this.setAVMetadataToController(itemId)
    this.currentPlayItem.set(this.mediaData.queueItems[itemId])
    this.currentAVMetadata.set(this.mediaData.avMetadataList[itemId])
    await MediaPlayer.instance.loadFromRawFile('test_44100_2.wav')
    MediaPlayer.instance.onCallback(AVPlayerState.PREPARED, () => {
      this.switchNewItemAVPlayback()
    })
  }

  // 切换会话播放状态
  async switchNewItemAVPlayback() {
    await this.localPlayOrPause()
    let isFavor = this.isFavorMap.get().get(this.currentAVMetadata.get().assetId) ?? false
    this.currentState = {
      state: this.isPlaying.get() ? avSession.PlaybackState.PLAYBACK_STATE_PLAY :
        avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
      position: {
        elapsedTime: this.currentTime,
        updateTime: new Date().getTime()
      },
      isFavorite: isFavor
    }
    this.session?.setAVPlaybackState(this.currentState, () => {
    })
  }

  //播放模式
  async loopMode() {
    let currentMode = this.currentLoopModel.get()
    this.currentLoopModel.set(currentMode === 3 ? 0 : currentMode + 1)
    this.currentState.loopMode = this.currentLoopModel.get()
    this.session?.setAVPlaybackState(this.currentState, () => {
    })
  }

  //收藏功能
  async toggleFavorite():Promise<void> {
    this.isFavorMap.get()
      .set(this.currentAVMetadata.get().assetId,
        !this.isFavorMap.get().get(this.currentAVMetadata!.get().assetId))
    this.currentState.isFavorite = this.isFavorMap.get().get(this.currentAVMetadata.get().assetId)
    this.session?.setAVPlaybackState(this.currentState, () => {
    })
  }

  // 进度
  async seek(value: number): Promise<void> {
    let currentPosition = value / 100 * (this.currentAVMetadata.get().duration ?? 0)
    if (currentPosition >= this.currentAVMetadata.get().duration!) {
      this.next()
    } else {
      this.avPlayer?.seek(currentPosition)
      this.currentState.position = {
        elapsedTime: Math.floor(currentPosition),
        updateTime: new Date().getTime()
      }
      this.session?.setAVPlaybackState(this.currentState, () => {
      })
    }
  }

  // //从数据源中通过itemId获取当前正在播放的AVMetadata并设置给对话
  // async setAVMetadataController(itemId:number):Promise<void>{
  //   let avMetadata:avSession.AVMetadata = this.mediaData.avMetadataList[itemId]
  //   await this.session?.setAVMetadata(avMetadata)
  //
  //   //————同步当前歌曲的收藏状态到AVPlaybackState————
  //   const currentAssetId = avMetadata.assetId //也可以从this.currentPlayItem.get()获取
  //   if (currentAssetId) {
  //     const currentIsFavorite = this.isFavorMap.get().get(currentAssetId) || false
  //     this.currentState.isFavorite = currentIsFavorite
  //     await this.session?.setAVPlaybackState(this.currentState)
  //   }
  //   //————结束————
  // }

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



/**
 * 播放或暂停
 */
  async playOrPause() {
    await this.localPlayOrPause()
    let isFavor = this.isFavorMap.get().get(this.currentAVMetadata.get().assetId) ?? false
    this.currentState = {
      state: this.isPlaying.get() ? avSession.PlaybackState.PLAYBACK_STATE_PLAY :
        avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
      position: {
        elapsedTime: this.currentTime,
        updateTime: new Date().getTime()
      },
      isFavorite: isFavor
    }
    this.session?.setAVPlaybackState(this.currentState, () => {
    })
  }

  //单独封装一个播放和暂停的方法，用于在提供方单独点击播放和暂停时可以把播放状态同步给控制方
  // async play():Promise<void>{
  //   this.localPlayOrPause()
  //   this.currentState = {
  //     state:this.isPlaying.get() ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
  //     position:{
  //       elapsedTime:this.currentTime,
  //       updateTime:new Date().getTime()
  //     }
  //   }
  //   await this.session?.setAVPlaybackState(this.currentState)
  // }
  //
  // async pause():Promise<void>{
  //   this.localPlayOrPause()
  //   this.currentState = {
  //     state:this.isPlaying.get() ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
  //     position:{
  //       elapsedTime:this.currentTime,
  //       updateTime:new Date().getTime()
  //     }
  //   }
  //   await this.session?.setAVPlaybackState(this.currentState)
  // }

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