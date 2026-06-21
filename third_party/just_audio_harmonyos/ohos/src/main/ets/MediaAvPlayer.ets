/**
 * Copyright (C) 2024 Huawei Device Co., Ltd.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 * */

import { media } from '@kit.MediaKit';
import { common, wantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AVCastPickerState, avSession } from '@kit.AVSessionKit';
import MediaSource from './MediaSource';
import { fileIo } from '@kit.CoreFileKit';
import { Log, MethodResult } from '@ohos/flutter_ohos';

const TAG = 'MediaAvPlayer';
const OPERATE_ERROR: number = 801;
const AVPLAYER_STATE_ERROR: number = 5400102;
const AVPLAYER_IO_ERROR: number = 5400103;

export enum AudioPlayerState {
  IDLE,
  INITIALIZED,
  LOAD,
  PREPARED,
  PLAY,
  PAUSE,
  STOP,
  ERROR,
  COMPLETED,
  RELEASED,
  PROGRESS_SPEED,
  TIME_UPDATE,
  VOLUME_CHANGE,
  UNKNOWN
}

export enum LoopMode {
  DEFAULT,
  SINGLE_CYCLE,
  LIST_LOOP
}

enum SeekMode {
  UNKNOWN,
  SEEK,
  FINISH
}

export enum PlaybackState {
  IDLE, STATE_READY, STATE_BUFFERING, STATE_ENDED
}

export interface onChangeMediaAvPlayerState {
  onPlaybackStateChanged(state: PlaybackState): void;

  onUpdateCurrentIndex(updateIndex: number): void;

  onUpdatePosition(updatePosition: number): void;

  onUpdateBufferedPosition(bufferedPosition: number): void;

  onAudioSessionIdChanged(audioSessionId: number): void;

  broadcastImmediatePlaybackEvent(): void;

  completeSeek(): void;

  completeInitial(): void;

  onStartBuffering(): void;

  onEndBuffering(): void;

  setAudioSessionId(audioSessionId: number): void

  onErrorCallback(err: BusinessError): void
}

export class MediaAvPlayer {
  private context: common.UIAbilityContext | undefined = AppStorage.get('context');
  public avPlayer: media.AVPlayer | null = null;
  public avPlayerNext: media.AVPlayer | null = null;
  public isPlaying: boolean = false;
  public songList: MediaSource[] = [];
  public state: AudioPlayerState = AudioPlayerState.IDLE;
  private session?: avSession.AVSession;
  private initialPos: number = -1;
  private initialIndex: number = -1;
  private volume: number = -1;
  private speed: number = 1;
  private playbackRate: number = 1;
  private seekModule: SeekMode = SeekMode.UNKNOWN;
  private playMode: LoopMode = LoopMode.DEFAULT;
  private isFirst: boolean = true;
  private isPrepared: boolean = false;
  private isClipping: boolean = false;
  private isPreBuffering: boolean = false;
  private isRandom: boolean = false;
  private musicIndex: number = 0;
  private preMusicIndex: number = 0;
  private songItem: MediaSource | null = null;
  private shuffleOrder: number[] = [];
  private avMetadataExtractor: media.AVMetadataExtractor | null = null;
  private avMetadata?: media.AVMetadata;
  public mediaAvPlayerStateChangeListener?: onChangeMediaAvPlayerState;
  // 播放策略
  private playStrategy: media.PlaybackStrategy = {
    //播放策略首选宽度，int类型，如1080。
    preferredWidth: 1,
    //播放策略首选高度，int类型，如1920。
    preferredHeight: 2,
    //播放策略首选缓冲持续时间，单位s，取值范围1-20。
    preferredBufferDuration: 1,
    //播放策略true是hdr，false非hdr，默认非hdr。
    preferredHdr: false
  };
  private seekIsFirst: number = -1
  private playMusicIndex: number = 0
  // dataSrc fd 跟随 current/next 播放器迁移；切歌、reset、dispose 时必须关闭对应 fd。
  private currentDataSrcFd: number | null = null
  private nextDataSrcFd: number | null = null
  private isDisposed: boolean = false
  // generation 用来让旧的异步初始化、预加载和 loadUri 回调自动失效。
  private lifecycleGeneration: number = 0
  private initGeneration: number = 0
  private nextPreloadInFlight: boolean = false
  private nextPreloadGeneration: number = -1
  private nextPreloadTask: Promise<void> | null = null
  // pending 表示下一首还在 loadUri；avPlayerNext 才表示可以被升格为 current。
  private pendingAvPlayerNext: media.AVPlayer | null = null
  // next 回调按具体 AVPlayer 绑定，避免延迟事件误操作新的 next player。
  private nextStateCallPlayer: media.AVPlayer | null = null
  private nextStateCall: ((state: string) => Promise<void>) | null = null
  private lastBufferedPosition: number = 0
  private lastAVSessionPlaybackStateUpdateTime: number = 0

  constructor() {
    const generation = ++this.initGeneration;
    this.initAudioPlayer(generation).catch((error: BusinessError) => {
      console.error(TAG, `init audio player failed, code is ${error.code}, message is ${error.message}`);
    });
  }

  setMediaAvPlayerStateChange(listener: onChangeMediaAvPlayerState) {
    this.mediaAvPlayerStateChangeListener = listener
  }

  private closeDataSrcFd(forNext: boolean = false): void {
    const fd = forNext ? this.nextDataSrcFd : this.currentDataSrcFd;
    if (fd === null) {
      return;
    }
    try {
      fileIo.closeSync(fd);
    } catch (error) {
      console.error(TAG, `close data src fd failed: ${JSON.stringify(error)}`);
    }
    if (forNext) {
      this.nextDataSrcFd = null;
    } else {
      this.currentDataSrcFd = null;
    }
  }

  private async releaseSession(session: avSession.AVSession | undefined, name: string): Promise<void> {
    if (!session) {
      return;
    }
    try {
      session.off('play', this.playCall);
      session.off('pause', this.pauseCall);
      session.off('playNext', this.playNextCall);
      session.off('playPrevious', this.playPreviousCall);
      session.off('seek', this.avSessionSeekCall);
    } catch (error) {
      console.error(TAG, `remove ${name} callbacks failed: ${JSON.stringify(error)}`);
    }
    try {
      await session.deactivate();
    } catch (error) {
      console.error(TAG, `deactivate ${name} failed: ${JSON.stringify(error)}`);
    }
    try {
      await session.destroy();
    } catch (error) {
      console.error(TAG, `destroy ${name} failed: ${JSON.stringify(error)}`);
    }
  }

  private async disposeSession(): Promise<void> {
    const session = this.session;
    this.session = undefined;
    await this.releaseSession(session, 'av session');
  }

  private notifyLoadError(errorCode: string, errorMessage: string): void {
    const error = new Error(errorMessage) as BusinessError<void>;
    error.name = errorCode;
    error.code = AVPLAYER_IO_ERROR;
    this.mediaAvPlayerStateChangeListener?.onErrorCallback(error);
  }

  private reportLoadUriError(errorCode: string, errorMessage: string, reportError: boolean): boolean {
    console.error(TAG, errorMessage);
    if (reportError) {
      this.state = AudioPlayerState.ERROR;
      this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_ERROR);
      this.notifyLoadError(errorCode, errorMessage);
    }
    return false;
  }

  private isStaleGeneration(generation: number): boolean {
    return this.isDisposed || generation != this.lifecycleGeneration;
  }

  private isStaleInitGeneration(generation: number): boolean {
    return this.isDisposed || generation != this.initGeneration;
  }

  private beginNextPreload(generation: number): boolean {
    // 同一时间只允许一个 next player 处于 pending 或已预加载状态。
    if (this.avPlayerNext != null || this.pendingAvPlayerNext != null || this.nextPreloadInFlight) {
      return false;
    }
    this.nextPreloadInFlight = true;
    this.nextPreloadGeneration = generation;
    return true;
  }

  private finishNextPreload(generation: number): void {
    if (this.nextPreloadGeneration == generation || this.nextPreloadGeneration == -1) {
      this.nextPreloadInFlight = false;
      this.nextPreloadGeneration = -1;
    }
  }

  private invalidateNextPreload(): void {
    // 不立刻清 inFlight；等待旧任务自然结束并释放自己持有的 AVPlayer/fd。
    this.nextPreloadGeneration = -1;
  }

  private async waitForNextPreload(): Promise<void> {
    const task = this.nextPreloadTask;
    if (!task) {
      return;
    }
    try {
      await task;
    } catch (error) {
      console.error(TAG, `wait next preload failed: ${JSON.stringify(error)}`);
    }
  }

  private async releasePendingNextPlayer(avPlayer: media.AVPlayer | null, name: string): Promise<void> {
    if (!avPlayer) {
      return;
    }
    if (this.pendingAvPlayerNext === avPlayer) {
      this.offAVPlayerNextCallback(avPlayer);
      this.pendingAvPlayerNext = null;
      this.closeDataSrcFd(true);
    }
    await this.releaseAvPlayer(avPlayer, name);
  }

  private isActiveNextPlayer(avPlayer: media.AVPlayer): boolean {
    return !this.isDisposed && (this.pendingAvPlayerNext === avPlayer || this.avPlayerNext === avPlayer);
  }

  private avSessionStateForCurrentState(): avSession.PlaybackState {
    switch (this.state) {
      case AudioPlayerState.INITIALIZED:
      case AudioPlayerState.LOAD:
      case AudioPlayerState.PROGRESS_SPEED:
        return avSession.PlaybackState.PLAYBACK_STATE_PREPARE;
      case AudioPlayerState.PLAY:
        return avSession.PlaybackState.PLAYBACK_STATE_PLAY;
      case AudioPlayerState.PREPARED:
      case AudioPlayerState.PAUSE:
        return avSession.PlaybackState.PLAYBACK_STATE_PAUSE;
      case AudioPlayerState.STOP:
        return avSession.PlaybackState.PLAYBACK_STATE_STOP;
      case AudioPlayerState.COMPLETED:
        return avSession.PlaybackState.PLAYBACK_STATE_COMPLETED;
      case AudioPlayerState.RELEASED:
        return avSession.PlaybackState.PLAYBACK_STATE_RELEASED;
      case AudioPlayerState.ERROR:
      case AudioPlayerState.UNKNOWN:
        return avSession.PlaybackState.PLAYBACK_STATE_ERROR;
      case AudioPlayerState.IDLE:
      default:
        return avSession.PlaybackState.PLAYBACK_STATE_INITIAL;
    }
  }

  private syncCurrentAVSessionPlaybackState(force: boolean = true): void {
    this.syncAVSessionPlaybackState(this.avSessionStateForCurrentState(), force);
  }

  private syncAVSessionPlaybackState(state: avSession.PlaybackState, force: boolean = true,
    bufferedTime?: number): void {
    if (!this.session) {
      return;
    }
    const now = new Date().getTime();
    if (!force && now - this.lastAVSessionPlaybackStateUpdateTime < 1000) {
      return;
    }
    this.lastAVSessionPlaybackStateUpdateTime = now;
    this.setPlayState({
      state: state,
      speed: this.isPlaying ? this.playbackRate : 0,
      position: {
        elapsedTime: this.getCurrentTime(),
        updateTime: now
      },
      bufferedTime: bufferedTime ?? this.lastBufferedPosition,
      activeItemId: this.musicIndex,
      duration: this.getDuration()
    });
  }

  private getAVSessionTitle(): string {
    const title = this.avMetadata?.title;
    if (title && title.trim().length > 0) {
      return title;
    }
    const id = this.songItem?.getId();
    if (id && id.trim().length > 0) {
      return id;
    }
    const uri = this.songItem?.getUri();
    if (uri && uri.trim().length > 0) {
      const cleanUri = uri.split('?')[0];
      const segments = cleanUri.split('/');
      const lastSegment = segments[segments.length - 1];
      if (lastSegment && lastSegment.length > 0) {
        return lastSegment;
      }
    }
    return 'AI Music';
  }

  private getAVSessionArtist(): string {
    const artist = this.avMetadata?.artist;
    if (artist && artist.trim().length > 0) {
      return artist;
    }
    return 'AI Music';
  }

  private async refreshAVSessionMetadata(): Promise<void> {
    try {
      if (this.avMetadataExtractor) {
        this.avMetadata = await this.avMetadataExtractor.fetchMetadata();
      }
    } catch (error) {
      console.error(TAG, `fetch AV metadata failed: ${JSON.stringify(error)}`);
    }
    this.setAVMetadata();
  }

  /**
   * 获取MediaAvPlayer实例
   * */
  public static getInstance(): MediaAvPlayer {
    let mediaAvPlayer: MediaAvPlayer | undefined = AppStorage.get('mediaService');
    if (!mediaAvPlayer) {
      mediaAvPlayer = new MediaAvPlayer();
      AppStorage.setOrCreate('mediaService', mediaAvPlayer);
    }
    return mediaAvPlayer;
  }

  private playCall: () => void = async () => {
    console.info(TAG, `on play , do play task`);
    if (this.isFirst) {
      await this.loadAssent(0);
    } else {
      this.play();
    }
  };
  private pauseCall: () => void = () => {
    console.info(TAG, `on pause , do pause task`);
    this.pause();
  };
  private playNextCall: () => void = () => {
    console.info(TAG, `on playNext , do playNext task`);
    this.playNextAuto();
  };
  private playPreviousCall: () => void = () => {
    console.info(TAG, `on playPrevious , do playPrevious task`);
    this.playPrevious();
  };
  private avSessionSeekCall: (time: number) => void = (time: number) => {
    console.info(TAG, `on seek , do seek task ${time}`);
    this.seek(time).catch((error: BusinessError) => {
      console.error(TAG, `session seek failed, code is ${error.code}, message is ${error.message}`);
      this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_ERROR);
    });
  };
  /**
   * 异常监听
   * */
  private errorCall: (err: BusinessError) => void = (err: BusinessError) => {
    if (err.code == OPERATE_ERROR || err.code == AVPLAYER_STATE_ERROR || err.code == AVPLAYER_IO_ERROR) {
      console.error(TAG, `AvPlayer Avoid Error Reporting: ${err}`);
      return;
    }
    console.error(TAG, `Invoke avPlayer failed, code is ${err.code}, message is ${err.message}`);
    this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_ERROR);
    this.loadAssent(this.musicIndex);
    this.mediaAvPlayerStateChangeListener?.onErrorCallback(err);
  };
  /**
   * 缓冲回调
   * */
  private bufferingUpdate: (infoType: media.BufferingInfoType, value: number) =>
  void = (infoType: media.BufferingInfoType, value: number) => {
    console.info(TAG, 'bufferingUpdate called,and infoType value is:' + infoType + ', value is :' + value);
    switch (infoType) {
      case media.BufferingInfoType.CACHED_DURATION:
        this.lastBufferedPosition = value;
        this.mediaAvPlayerStateChangeListener?.onUpdateBufferedPosition(value);
        this.syncCurrentAVSessionPlaybackState(false);
        break;
      case media.BufferingInfoType.BUFFERING_START:
        this.mediaAvPlayerStateChangeListener?.onStartBuffering();
        this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PREPARE);
        break;
      case media.BufferingInfoType.BUFFERING_PERCENT:
        if (value < 100) {
          this.mediaAvPlayerStateChangeListener?.onStartBuffering();
          this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PREPARE, false);
        } else if (this.seekModule != SeekMode.SEEK) {
          this.mediaAvPlayerStateChangeListener?.onEndBuffering();
          this.syncCurrentAVSessionPlaybackState(false);
        }
        break;
      case media.BufferingInfoType.BUFFERING_END:
        if (this.seekModule != SeekMode.SEEK) {
          this.mediaAvPlayerStateChangeListener?.onEndBuffering();
          this.syncCurrentAVSessionPlaybackState();
        }
        break;
    }
  }
  /**
   * 下一曲缓冲回调
   * */
  private bufferingUpdateNext: (infoType: media.BufferingInfoType, value: number) =>
  void = (infoType: media.BufferingInfoType, value: number) => {
    console.info(TAG, 'bufferingUpdateNext called,and infoType value is:' + infoType + ', value is :' + value);
  }
  /**
   * 监听资源播放当前时间，单位为毫秒（ms），用于刷新进度条当前位置，默认间隔100ms时间上报，因用户操作(seek)产生的时间变化会立刻上报
   * */
  private updateTimeCall: (updateTime: number) => void = (updateTime: number) => {
    if (this.volume != -1) {
      this.avPlayer?.setVolume(this.volume);
      this.volume = -1;
    }
    this.avPlayer?.setSpeed(this.speed);
    if (this.isClipping) {
      if (this.avPlayer && updateTime > 0 && this.getDuration() > 0 &&
        (this.songItem!.getEndUs() / 1000) < updateTime) {
        this.seek(this.playMode != LoopMode.SINGLE_CYCLE ? this.avPlayer.duration :
          (this.songItem!.getStartUs() / 1000));
      }
    }
    this.syncCurrentAVSessionPlaybackState(false);
  };
  /**
   * 进度条拖动回调,拖动松手后不会立刻回调,完成后回调
   * */
  private seekCall: (seekDoneTime: number) => void = async (seekDoneTime: number) => {
    this.mediaAvPlayerStateChangeListener?.completeSeek();
    this.seekModule = SeekMode.FINISH;
    if (this.state == AudioPlayerState.PREPARED || this.state == AudioPlayerState.PLAY ||
      this.state == AudioPlayerState.PAUSE || this.state == AudioPlayerState.COMPLETED) {
      this.playingState();
    }
    this.syncCurrentAVSessionPlaybackState();
    console.info(TAG, `AVPlayer seek succeeded, seek time is ${seekDoneTime}`);
  };
  /**
   *订阅录制状态机AVRecorderState切换的事件，当 AVRecorderState状态机发生变化时，会通过订阅的回调方法通知用户。用户只能订阅一个状态机切换事件的回调方法，当用户重复订阅时，以最后一次订阅的回调接口为准
   * */
  private stateCall: (state: string) => Promise<void> = async (state: string) => {
    if (this.isDisposed) {
      return;
    }
    switch (state) {
      case 'idle':
        console.info(TAG, 'AVPlayer state idle called.');
        this.state = AudioPlayerState.IDLE;
        this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_INITIAL);
        if (this.avPlayerNext == null && this.pendingAvPlayerNext == null && !this.nextPreloadInFlight) {
          this.offAVPlayerNextCallback();
          this.preMusicIndex = this.musicIndex + 1;
          let nextSong: MediaSource = this.songList[this.preMusicIndex];
          if (this.musicIndex == this.songList.length - 1) {
            if (this.playMode == LoopMode.LIST_LOOP) {
              this.preMusicIndex = 0;
              nextSong = this.songList[this.preMusicIndex];
            }
          }
          if (this.isRandom && this.shuffleOrder.length == this.songList.length) {
            let currentIndex = this.shuffleOrder.indexOf(this.musicIndex);
            if (currentIndex != -1) {
              if (currentIndex == this.shuffleOrder.length - 1) {
                this.preMusicIndex = this.shuffleOrder[0];
              } else {
                this.preMusicIndex = this.shuffleOrder[currentIndex+1];
              }
              nextSong = this.songList[this.preMusicIndex];
            }
          }
          if (nextSong) {
            const preloadGeneration = this.lifecycleGeneration;
            if (!this.beginNextPreload(preloadGeneration)) {
              break;
            }
            const preloadTask = media.createAVPlayer().then(async (value: media.AVPlayer) => {
              const nextPlayer = value;
              try {
                if (this.isStaleGeneration(preloadGeneration) ||
                  this.nextPreloadGeneration != preloadGeneration || this.avPlayerNext != null ||
                  this.pendingAvPlayerNext != null) {
                  await this.releaseAvPlayer(nextPlayer, 'stale avPlayerNext');
                  return;
                }
                this.pendingAvPlayerNext = nextPlayer;
                this.setAVPlayerNextCallback(nextPlayer);
                let nextUrl = nextSong.getUri();
                if (!nextUrl) {
                  await this.releasePendingNextPlayer(nextPlayer, 'empty uri avPlayerNext');
                  return;
                }
                if (nextPlayer.state == "idle") {
                  const loaded = await this.loadUri(nextPlayer, nextUrl, false, preloadGeneration);
                  if (!loaded) {
                    await this.releasePendingNextPlayer(nextPlayer, 'failed avPlayerNext');
                    return;
                  }
                }
                if (this.isStaleGeneration(preloadGeneration) ||
                  this.nextPreloadGeneration != preloadGeneration || this.avPlayerNext != null ||
                  this.pendingAvPlayerNext !== nextPlayer) {
                  await this.releasePendingNextPlayer(nextPlayer, 'stale avPlayerNext');
                  return;
                }
                // loadUri 成功后才发布为 avPlayerNext，避免半初始化播放器被切歌逻辑接管。
                this.pendingAvPlayerNext = null;
                this.avPlayerNext = nextPlayer;
              } catch (error) {
                await this.releasePendingNextPlayer(nextPlayer, 'failed avPlayerNext');
                console.error(TAG, `preload next AVPlayer failed: ${JSON.stringify(error)}`);
              } finally {
                this.finishNextPreload(preloadGeneration);
              }
            }).catch((error: BusinessError) => {
              this.finishNextPreload(preloadGeneration);
              console.error(TAG, `create next AVPlayer failed, code is ${error.code}, message is ${error.message}`);
            });
            this.nextPreloadTask = preloadTask;
          }
        }
        break;
      case 'initialized':
        console.info(TAG, 'AVPlayer state initialized called.');
        this.state = AudioPlayerState.INITIALIZED;
        this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PREPARE);
        if (this.avPlayer) {
          this.avPlayer.prepare().then(() => {
            console.info(TAG, 'AVPlayer prepare succeeded.');
          }, (err: BusinessError) => {
            console.error(TAG, `Invoke prepare failed, code is ${err.code}, message is ${err.message}`);
          });
        }
        break;
      case 'prepared':
        this.state = AudioPlayerState.PREPARED;
        this.isPrepared = true
        console.info(TAG, 'AVPlayer prepared .');
        await this.refreshAVSessionMetadata();
        if (this.initialPos != -1 && this.initialIndex != -1 && this.initialIndex == this.musicIndex) {
          this.seek(this.initialPos);
          this.initialPos = -1;
          this.initialIndex = -1;
          this.mediaAvPlayerStateChangeListener?.completeInitial();
          this.mediaAvPlayerStateChangeListener?.onPlaybackStateChanged(PlaybackState.STATE_READY);
          this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PAUSE);
          break;
        }
        if (this.isClipping) {
          this.avPlayer?.seek(this.songItem!.getStartUs() / 1000);
          this.mediaAvPlayerStateChangeListener?.onPlaybackStateChanged(PlaybackState.STATE_BUFFERING);
          this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PREPARE);
          break;
        }
        if (this.isPreBuffering) {
          this.isPreBuffering = false;
          this.playMusicIndex = this.musicIndex;
        }
        if (this.playMusicIndex == this.musicIndex) {
          this.playingState();
        } else {
          this.songItem = this.songList[this.musicIndex];
          let url = this.songItem?.getUri();
          if (url && this.avPlayer?.state == "idle") {
            const loaded = await this.loadUri(this.avPlayer, url, true, this.lifecycleGeneration);
            if (!loaded) {
              break;
            }
          }
        }
        this.syncAVSessionPlaybackState(
          this.isPlaying ? avSession.PlaybackState.PLAYBACK_STATE_PREPARE : avSession.PlaybackState.PLAYBACK_STATE_PAUSE);
        break;
      case 'playing':
        console.info(TAG, 'AVPlayer state playing called.');
        this.seekIsFirst = -1
        this.isPlaying = true;
        this.state = AudioPlayerState.PLAY;
        this.mediaAvPlayerStateChangeListener?.onEndBuffering();
        this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PLAY);
        break;
      case 'paused':
        console.info(TAG, 'AVPlayer state paused called.');
        this.isPlaying = false;
        this.state = AudioPlayerState.PAUSE;
        this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PAUSE);
        break;
      case 'completed':
        console.info(TAG, 'AVPlayer state completed called.');
        this.state = AudioPlayerState.COMPLETED;
        this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_COMPLETED);
        if ((this.playMode == LoopMode.DEFAULT && this.musicIndex == this.songList.length - 1) ||
          this.songList.length == 0) {
          this.mediaAvPlayerStateChangeListener?.onPlaybackStateChanged(PlaybackState.STATE_ENDED);
        }
        this.playNextAuto();
        break;
      case 'stopped':
        console.info(TAG, 'AVPlayer state stopped called.');
        this.state = AudioPlayerState.STOP;
        this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_STOP);
        break;
      case 'released':
        console.info(TAG, 'AVPlayer state released called.');
        this.state = AudioPlayerState.RELEASED;
        this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_RELEASED);
        break;
      default:
        console.info(TAG, 'AVPlayer state unknown called.');
        this.state = AudioPlayerState.UNKNOWN;
        this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_ERROR);
        this.loadAssent(this.musicIndex)
        break;
    }
  };
  private async handlePreStateCall(avPlayer: media.AVPlayer, state: string): Promise<void> {
    if (!this.isActiveNextPlayer(avPlayer)) {
      return;
    }
    switch (state) {
      case 'idle':
        console.info(TAG, 'avPlayerNext state idle called.');
        break;
      case 'initialized':
        console.info(TAG, 'avPlayerNext state initialized called.');
        avPlayer.prepare().then(() => {
          console.info(TAG, 'avPlayerNext AVPlayer prepare succeeded.');
        }, (err: BusinessError) => {
          console.error(TAG, `avPlayerNext Invoke prepare failed, code is ${err.code}, message is ${err.message}`);
        });
        break;
      case 'prepared':
        if (this.isPreBuffering) {
          console.info(TAG, 'avPlayerNext state isPreBuffering ');
          this.isPreBuffering = false;
          this.playingState();
        }
        console.info(TAG, 'avPlayerNext state prepared ');
        break;
      case 'playing':
        console.info(TAG, 'avPlayerNext state playing called.');
        break;
      case 'paused':
        console.info(TAG, 'avPlayerNext state paused called.');
        break;
      case 'completed':
        console.info(TAG, 'avPlayerNext state completed called.');
        break;
      case 'stopped':
        console.info(TAG, 'avPlayerNext state stopped called.');
        break;
      case 'released':
        console.info(TAG, 'avPlayerNext state released called.');
        break;
      default:
        console.info(TAG, 'avPlayerNext state unknown called.');
        break;
    }
  }

  playingState() {
    if (this.isPlaying) {
      this.avPlayer?.play().then(() => {
        console.info(TAG, 'AVPlayer play succeeded.');
        this.mediaAvPlayerStateChangeListener?.onPlaybackStateChanged(PlaybackState.STATE_READY);
        this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PLAY);
      }, (err: BusinessError) => {
        console.error(TAG, `Invoke play failed, code is ${err.code}, message is ${err.message}`);
        this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_ERROR);
      });
    } else if (this.avPlayer?.state == 'prepared' || this.avPlayer?.state == 'paused') {
      this.mediaAvPlayerStateChangeListener?.onPlaybackStateChanged(PlaybackState.STATE_READY);
      this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PAUSE);
    }
  }

  setAVPlayerNextCallback(avPlayer: media.AVPlayer | null = this.avPlayerNext) {
    if (!avPlayer) {
      return;
    }
    if (this.nextStateCallPlayer && this.nextStateCallPlayer !== avPlayer) {
      this.offAVPlayerNextCallback(this.nextStateCallPlayer);
    } else {
      this.offAVPlayerNextCallback(avPlayer);
    }
    // AVPlayer 的 stateChange 回调没有事件源参数，因此用闭包固定当前 next player。
    const stateCall = async (state: string): Promise<void> => {
      await this.handlePreStateCall(avPlayer, state);
    };
    this.nextStateCallPlayer = avPlayer;
    this.nextStateCall = stateCall;
    avPlayer.on('stateChange', stateCall);
    avPlayer.on('bufferingUpdate', this.bufferingUpdateNext);
  }


  offAVPlayerNextCallback(avPlayer: media.AVPlayer | null = this.avPlayerNext ?? this.pendingAvPlayerNext) {
    if (!avPlayer) {
      return;
    }
    if (this.nextStateCall && this.nextStateCallPlayer === avPlayer) {
      avPlayer.off('stateChange', this.nextStateCall);
      this.nextStateCall = null;
      this.nextStateCallPlayer = null;
    }
    avPlayer.off('bufferingUpdate', this.bufferingUpdateNext);
  }


  setListenerForMesFromController() {
    if (!this.session) {
      return;
    }
    this.session.on('play', this.playCall);
    this.session.on('pause', this.pauseCall);
    this.session.on('playNext', this.playNextCall);
    this.session.on('playPrevious', this.playPreviousCall);
    this.session.on('seek', this.avSessionSeekCall);
  }

  /**
   * 为服务设置回调监听
   * */
  private setAVPlayerCallback() {
    if (!this.avPlayer) {
      return;
    }
    this.avPlayer.on('seekDone', this.seekCall);

    this.avPlayer.on('error', this.errorCall);

    this.avPlayer.on('timeUpdate', this.updateTimeCall);

    this.avPlayer.on('bufferingUpdate', this.bufferingUpdate);

    this.avPlayer.on('stateChange', this.stateCall);

  }

  /**
   * 为服务注销回调监听
   * */
  private offAVPlayerCallback() {
    if (!this.avPlayer) {
      return;
    }
    this.avPlayer.off('seekDone', this.seekCall);

    this.avPlayer.off('error', this.errorCall);

    this.avPlayer.off('timeUpdate', this.updateTimeCall);

    this.avPlayer.off('bufferingUpdate', this.bufferingUpdate);

    this.avPlayer.off('stateChange', this.stateCall);

  }

  /**
   * Play previous music.
   */
  public async playPrevious() {


    switch (this.playMode) {
      case LoopMode.LIST_LOOP:
      case LoopMode.DEFAULT:
        if (this.isRandom) {
          this.playRandom();
          break;
        }
        if (this.musicIndex === 0) {
          this.updateMusicIndex(this.songList.length - 1);
        } else {
          this.updateMusicIndex(this.musicIndex - 1);
        }
        this.loadAssent(this.musicIndex);
        break;
      default:
        break;
    }
  }

  private updateMusicIndex(musicIndex: number) {
    this.mediaAvPlayerStateChangeListener?.onUpdateCurrentIndex(musicIndex)
    if (this.musicIndex !== musicIndex) {
      this.musicIndex = musicIndex;
    }
    if (this.session !== undefined) {
      this.setAVMetadata();
      this.syncCurrentAVSessionPlaybackState();
    }
  }

  async setAVMetadata() {
    let id = this.musicIndex;
    try {
      let metadata: avSession.AVMetadata = {
        assetId: `${id}`,
        title: this.getAVSessionTitle(),
        artist: this.getAVSessionArtist(),
        duration: this.getDuration()
      };
      if (this.session) {
        this.session.setAVMetadata(metadata).then(() => {
          console.info(TAG, 'SetAVMetadata successfully');
        }).catch((err: BusinessError) => {
          console.error(TAG, `SetAVMetadata BusinessError: code: ${err.code}, message: ${err.message}`);
        });
      }
    } catch (error) {
      console.error(TAG,
        `SetAVMetadata try: code: ${(error as BusinessError).code},message: ${(error as BusinessError).message}`);
    }
  }

  public getDuration() {
    if (this.isPrepared && this.avPlayer) {
      if (this.isClipping && this.songItem) {
        let duration = this.songItem.getEndUs() - this.songItem.getStartUs();
        return duration / 1000;
      }
      return this.avPlayer.duration;
    }
    return 0;
  }

  public setLoopMode(loopMode: number) {
    this.playMode = loopMode;
  }

  public setShuffleMode(isShuffle: boolean) {
    this.isRandom = isShuffle;
  }

  public setVolume(volume: number) {
    this.volume = volume
    this.avPlayer?.setVolume(volume);
  }

  public setSpeed(speed: number) {
    this.playbackRate = speed;
    switch (speed) {
      case 0.5:
      case 0.6:
        //x0.5
        this.speed = 5;
        break;
      case 0.7:
      case 0.8:
        //x0.75
        this.speed = 0;
        break;
      case 0.9:
      case 1:
      case 1.1:
        //x1
        this.speed = 1;
        break;
      case 1.2:
      case 1.3:
        //x1.25
        this.speed = 2;
        break;
      case 1.4:
      case 1.5:
        //x1.5
        this.speed = 6;
        break;
    }
    this.avPlayer?.setSpeed(this.speed);
    this.syncCurrentAVSessionPlaybackState();
  }

  /**
   * 初始化音频播放器
   * */
  async initAudioPlayer(generation: number) {
    if (!this.avPlayer) {
      const avPlayer = await media.createAVPlayer();
      if (this.isStaleInitGeneration(generation)) {
        await this.releaseAvPlayer(avPlayer, 'stale init avPlayer');
        return;
      }
      this.avPlayer = avPlayer;
    }
    const avMetadataExtractor = await media.createAVMetadataExtractor();
    if (this.isStaleInitGeneration(generation)) {
      await this.releaseMetadataExtractorInstance(avMetadataExtractor, 'stale init metadata extractor');
      return;
    }
    this.avMetadataExtractor = avMetadataExtractor;
    this.setAVPlayerCallback();
    await this.createSession(generation);
  }

  async createSession(generation: number = this.initGeneration) {
    if (!this.context || this.session || this.isStaleInitGeneration(generation)) {
      return;
    }
    const session = await avSession.createAVSession(this.context, 'SESSION_NAME', 'audio');
    if (this.isStaleInitGeneration(generation) || this.session) {
      await this.releaseSession(session, 'stale av session');
      return;
    }
    this.session = session;
    await session.activate();
    if (this.isStaleInitGeneration(generation)) {
      await this.disposeSession();
      return;
    }
    this.setAVMetadata();
    let wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: this.context.abilityInfo.bundleName,
          abilityName: this.context.abilityInfo.name
        }
      ],
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    }
    wantAgent.getWantAgent(wantAgentInfo).then((agent) => {
      if (this.session === session && !this.isStaleInitGeneration(generation)) {
        session.setLaunchAbility(agent);
      }
    })
    this.mediaAvPlayerStateChangeListener?.setAudioSessionId(parseInt(session.sessionId))
    this.setListenerForMesFromController();
    this.syncCurrentAVSessionPlaybackState();
  }

  /**
   * Play music.
   */
  public async play(result?: MethodResult) {
    this.isPlaying = true;
    if (!this.isPrepared) {
      this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PREPARE);
      this.start(0);
    } else if (this.avPlayer) {
      this.avPlayer.play().then(() => {
        this.updateIsPlay(true);
        this.state = AudioPlayerState.PLAY;
        result?.success(new Map<String, Object>());
      }).catch((e: BusinessError) => {
        result?.error(e.code.toString(), e.message, e.data);
        console.error(TAG, "play::error:" + e.message);
        this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_ERROR);
      })
    }
  }

  /**
   * Pause music.
   */
  public pause(result?: MethodResult) {
    if (this.isPlaying && this.avPlayer) {
      this.isPlaying = false;
      this.avPlayer.pause().then(() => {
        this.state = AudioPlayerState.PAUSE;
        this.updateIsPlay(false);
        result?.success(new Map<String, Object>());
      }).catch((e: BusinessError) => {
        result?.error(e.code.toString(), e.message, e.data)
        console.error(TAG, "pause::error" + e.message);
        this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_ERROR);
      });
    }
  }

  /**
   * Play next music.
   *
   * @param isFromControl
   */
  public async playNextAuto() {


    switch (this.playMode) {
      case LoopMode.SINGLE_CYCLE:
        if (this.avPlayer) {
          this.avPlayer.loop = true;
          this.loadAssent(this.musicIndex);
        }
        break;
      case LoopMode.LIST_LOOP:
      case LoopMode.DEFAULT:
        if (this.avPlayer) {
          this.avPlayer.loop = false;
        }
        if (this.isRandom) {
          this.playRandom();
        } else {
          this.playNext();
        }
        break;
      default:
        break;
    }
  }

  /**
   * Play music by index.
   *
   * @param musicIndex
   */
  async loadAssent(musicIndex: number) {
    if (this.isDisposed) {
      return;
    }
    const generation = ++this.lifecycleGeneration;
    this.invalidateNextPreload();
    if (this.seekModule == SeekMode.SEEK) {
      this.seekModule = SeekMode.UNKNOWN;
    }
    if (musicIndex >= this.songList.length) {
      musicIndex = this.songList.length - 1;
      console.error(TAG, `current musicIndex ${musicIndex}`);
      this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_ERROR);
      return;
    }
    this.lastBufferedPosition = 0;
    this.mediaAvPlayerStateChangeListener?.onPlaybackStateChanged(PlaybackState.STATE_BUFFERING);
    this.mediaAvPlayerStateChangeListener?.onUpdateBufferedPosition(0);
    this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PREPARE, true, 0);
    this.songItem = this.songList[musicIndex];
    this.avMetadata = undefined;
    this.isClipping = this.songItem.type == "clipping";
    this.updateMusicIndex(musicIndex);
    if (this.avPlayerNext && this.preMusicIndex == musicIndex && !this.isFirst) {
      const promotedPlayer = this.avPlayerNext;
      this.offAVPlayerCallback();
      await this.avPlayer?.release();
      this.closeDataSrcFd(false);
      // 升格前必须摘掉 next 回调，再挂 current 回调，避免同一 AVPlayer 进入两套状态机。
      this.offAVPlayerNextCallback(promotedPlayer);
      this.avPlayerNext = null;
      this.avPlayer = promotedPlayer;
      this.currentDataSrcFd = this.nextDataSrcFd;
      this.nextDataSrcFd = null;
      this.setAVPlayerCallback();
      this.playMusicIndex = musicIndex;
      await this.refreshAVSessionMetadata();
      if (promotedPlayer.state == 'prepared') {
        this.playingState();
      } else {
        this.isPreBuffering = true;
      }
    } else {
      if (this.avPlayer) {
        if (this.avPlayerNext) {
          this.offAVPlayerNextCallback();
          await this.avPlayerNext.release();
          this.closeDataSrcFd(true);
        }
        this.avPlayerNext = null;
        if (this.isFirst) {
          this.isFirst = false;
        } else {
          await this.avPlayer.reset();
          this.closeDataSrcFd(false);
          this.playMusicIndex = musicIndex;
        }
        let url = this.songItem?.getUri();
        if (url && this.avPlayer.state == "idle") {
          const loaded = await this.loadUri(this.avPlayer, url, true, generation);
          if (!loaded) {
            return;
          }
        }
      }
    }
  }

  private async releaseAvPlayer(avPlayer: media.AVPlayer | null, name: string): Promise<void> {
    if (!avPlayer) {
      return;
    }
    try {
      await avPlayer.release();
    } catch (error) {
      console.error(TAG, `${name} release failed: ${JSON.stringify(error)}`);
    }
  }

  private async releaseMetadataExtractorInstance(avMetadataExtractor: media.AVMetadataExtractor | null,
    name: string): Promise<void> {
    if (!avMetadataExtractor) {
      return;
    }
    try {
      await avMetadataExtractor.release();
    } catch (error) {
      console.error(TAG, `${name} release failed: ${JSON.stringify(error)}`);
    }
  }

  private async releaseMetadataExtractor(): Promise<void> {
    await this.releaseMetadataExtractorInstance(this.avMetadataExtractor, 'metadata extractor');
  }

  async dispose(): Promise<void> {
    if (this.isDisposed) {
      return;
    }
    this.isDisposed = true;
    this.lifecycleGeneration++;
    this.initGeneration++;
    this.invalidateNextPreload();
    this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_RELEASED);
    await this.waitForNextPreload();
    this.offAVPlayerCallback();
    this.offAVPlayerNextCallback();
    await this.disposeSession();
    await this.releaseAvPlayer(this.avPlayer, 'avPlayer');
    await this.releaseAvPlayer(this.avPlayerNext, 'avPlayerNext');
    await this.releasePendingNextPlayer(this.pendingAvPlayerNext, 'pending avPlayerNext');
    await this.releaseMetadataExtractor();
    this.closeDataSrcFd(false);
    this.closeDataSrcFd(true);
    this.avMetadataExtractor = null;
    this.avPlayerNext = null;
    this.avPlayer = null;
  }

  private playNext() {
    if (this.musicIndex === this.songList.length - 1) {
      if (this.playMode == LoopMode.LIST_LOOP) {
        this.loadAssent(0);
      }
    } else {
      this.loadAssent(this.musicIndex + 1);
    }
  }

  private playRandom() {
    if (this.shuffleOrder.length == 0) {
      let num = Math.round(Math.random() * (this.songList.length - 1));
      if (this.musicIndex === num) {
        this.playRandom();
      } else {
        this.updateMusicIndex(num);
        this.loadAssent(num);
      }
    } else {
      let orderIndex = this.shuffleOrder.indexOf(this.musicIndex);
      let num = orderIndex == this.shuffleOrder.length - 1 ? 0 : orderIndex + 1;
      this.updateMusicIndex(this.shuffleOrder[num]);
      this.loadAssent(this.shuffleOrder[num]);
    }
  }

  /**
   * Seek play music.
   *
   * @param ms.
   */
  public async seek(ms: number, index?: number) {

    this.mediaAvPlayerStateChangeListener?.onStartBuffering();
    this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PREPARE);
    if (ms == this.avPlayer?.duration) {
      if (this.isRandom) {
        this.playRandom();
      } else if (this.playMode == LoopMode.LIST_LOOP) {
        this.playNext()
      } else {
        this.avPlayer.seek(this.avPlayer?.duration);
      }
      return;
    }

    let seekMode = this.getCurrentTime() < ms ? 0 : 1;
    if (this.isClipping) {
      ms = this.songItem!.getStartUs() / 1000 + ms;
    }
    let realTime = ms <= 0 ? 0 : ms;
    if (index || index == 0 && this.musicIndex != index) {
      await this.avPlayer?.reset();
      this.closeDataSrcFd(false);
      await this.loadAssent(index);
    } else {
      if ((this.state == AudioPlayerState.PREPARED || this.state == AudioPlayerState.PLAY ||
        this.state == AudioPlayerState.COMPLETED || this.state == AudioPlayerState.PAUSE) && this.avPlayer) {
        this.seekModule = SeekMode.SEEK;
        this.avPlayer.seek(realTime, seekMode);
      }
    }
  }

  private async loadUri(avPlayer: media.AVPlayer, uri: string, reportError: boolean = true,
    generation: number = this.lifecycleGeneration): Promise<boolean> {
    if (this.isStaleGeneration(generation)) {
      return false;
    }
    const isNextPlayer = avPlayer === this.avPlayerNext || avPlayer === this.pendingAvPlayerNext;
    if (uri?.startsWith('http')) {
      try {
        this.closeDataSrcFd(isNextPlayer);
        let headers: Record<string, string> = { "User-Agent": "User-Agent-Value" };
        if (this.songItem?.getHeader()) {
          headers = this.songItem?.getHeader() as Record<string, string>
        }
        let mediaSource: media.MediaSource = media.createMediaSourceWithUrl(uri, headers);
        avPlayer.setMediaSource(mediaSource, this.playStrategy);
        return true;
      } catch (error) {
        return this.reportLoadUriError('loadHttpDataSrcFailed',
          `load http data src failed: ${JSON.stringify(error)}`, reportError);
      }
    } else if (uri?.startsWith('file')) {
      if (this.context) {
        const dartFilePrefix = 'file:///';
        if (uri.startsWith(dartFilePrefix)) {
          uri = uri.slice(dartFilePrefix.length);
        }
        this.closeDataSrcFd(isNextPlayer);
        let openedFd: number | null = null;
        try {
          const dataSrcFd: number = fileIo.openSync(uri).fd;
          openedFd = dataSrcFd;
          let fileSize: number = fileIo.statSync(uri).size;
          let src: media.AVDataSrcDescriptor = {
            fileSize: fileSize,
            callback: (buf: ArrayBuffer, length: number, pos: number | undefined) => {
              let num = 0;
              if (buf == undefined || length == undefined || pos == undefined) {
                return -1;
              }
              num = fileIo.readSync(dataSrcFd, buf, { offset: pos, length: length });
              if (num > 0 && (fileSize >= pos)) {
                return num;
              }
              return -1;
            }
          }
          src.fileSize = fileSize;
          avPlayer.dataSrc = src;
          if (isNextPlayer) {
            this.nextDataSrcFd = dataSrcFd;
          } else {
            this.currentDataSrcFd = dataSrcFd;
          }
          openedFd = null;
          if (this.avMetadataExtractor) {
            this.avMetadataExtractor.dataSrc = src;
          }
          return true;
        } catch (error) {
          if (openedFd !== null) {
            try {
              fileIo.closeSync(openedFd);
            } catch (closeError) {
              console.error(TAG, `close failed data src fd failed: ${JSON.stringify(closeError)}`);
            }
          }
          return this.reportLoadUriError('loadFileDataSrcFailed',
            `load file data src failed: ${JSON.stringify(error)}`, reportError);
        }
      }
      return this.reportLoadUriError('loadFileDataSrcFailed',
        'load file data src failed: missing HarmonyOS ability context', reportError);
    } else {
      if (this.context) {
        this.closeDataSrcFd(isNextPlayer);
        let fileDescriptor = await getContext(this).resourceManager.getRawFd(uri)
          .catch((error: BusinessError) => {
            console.error(`resourceManager error code ${error.code} message ${error.message}`);
          });
        if (this.isStaleGeneration(generation)) {
          return false;
        }
        if (fileDescriptor) {
          let avFileDescriptor: media.AVFileDescriptor =
            { fd: fileDescriptor.fd, offset: fileDescriptor.offset, length: fileDescriptor.length };
          if (this.avMetadataExtractor) {
            this.avMetadataExtractor.fdSrc = avFileDescriptor;
          }
          avPlayer.fdSrc = avFileDescriptor;
          return true;
        }
      }
      return this.reportLoadUriError('loadRawDataSrcFailed',
        'load raw data src failed: missing resource descriptor', reportError);
    }
  }

  public addPublicMediaSources(index: number, mediaSources: Array<MediaSource>) {
    mediaSources.forEach((mediaSource: MediaSource) => {
      this.songList.push(mediaSource);
    });
    if (this.songList.length == 1 && this.avPlayer?.state == 'idle') {
      this.isFirst = true;
      this.loadAssent(0)
    }
  }

  public async removeMediaSourceRange(startIndex: number, endIndex: number) {
    this.songList.splice(startIndex, 1);
    if (this.songList.length > 0) {
      if (startIndex == this.songList.length) {
        this.loadAssent(this.songList.length - 1);
      } else if (startIndex == this.musicIndex) {
        this.loadAssent(this.musicIndex);
      }
    }
    this.updateCurrentIndex();
  }

  public moveMediaSource(currentIndex: number, newIndex: number) {
    let moveItem = this.songList.splice(currentIndex, 1);
    this.songList.splice(newIndex, 0, moveItem[0]);
    this.updateCurrentIndex();
  }

  private updateCurrentIndex() {
    let index = this.songList.indexOf(this.songItem!);
    if (index != -1) {
      this.musicIndex = index;
      this.mediaAvPlayerStateChangeListener?.onUpdateCurrentIndex(index);
    }
  }

  public setShuffleOrder(shuffleOrder: number[]) {
    this.shuffleOrder = shuffleOrder;
  }

  private getChildList(playList: MediaSource[]): MediaSource[] {
    if (playList.length == 1 && playList[0].getType() === 'concatenating') {
      return this.getChildList(playList[0].getChildMediaSource());
    }
    return playList;
  }

  public async load(mediaSource: MediaSource, currentIndex: number, seekPostion: number = 0) {
    if (this.isDisposed) {
      return;
    }
    this.lifecycleGeneration++;
    this.invalidateNextPreload();
    this.initialPos = seekPostion ?? -1;
    if (this.initialPos != -1) {
      this.initialIndex = currentIndex
    }
    if (this.playMode != LoopMode.DEFAULT) {
      mediaSource.setMusicPlayMode(this.playMode);
    }
    let mSource: media.MediaSource;
    let mediaType = mediaSource.getType();
    if (mediaType == "concatenating") {
      this.songList = this.getChildList(mediaSource.getChildMediaSource())
      this.playMode = mediaSource.getMusicPlayMode();
      this.setShuffleOrder(mediaSource.shuffleOrder);
      this.loadAssent(currentIndex);
    } else {
      this.songList = [mediaSource];
      if (mediaType == "clipping") {
        this.loadAssent(currentIndex);
      } else if (mediaSource.getHeader()) {
        mSource = media.createMediaSourceWithUrl(mediaSource.getUri(), mediaSource.getHeader());
        await this.avPlayer?.setMediaSource(mSource, this.playStrategy);
        await this.avPlayer?.prepare();
      } else {
        this.loadAssent(currentIndex)
      }
    }
  }

  public stop() {
    this.avPlayer?.stop();
    this.state = AudioPlayerState.STOP;
    this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_STOP);
  }

  private start(seekMs?: number) {
    if (this.avPlayer) {
      this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PREPARE);
      this.avPlayer.prepare().then(() => {
      }).catch((error: BusinessError) => {
        console.error(TAG, `start error ${JSON.stringify(error)}`);
        this.state = AudioPlayerState.ERROR;
        this.syncAVSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_ERROR);
        this.isPrepared = false;
      });
    }
  }

  private updateIsPlay(display: boolean) {
    this.syncAVSessionPlaybackState(
      display ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE);
  }

  public getCurrentTime() {
    if (this.isPrepared && this.avPlayer) {
      if (this.isClipping) {
        return this.avPlayer.currentTime - (this.songItem!.getStartUs() / 1000);
      }
      if (this.initialPos != -1 && this.initialPos != 0) {
        this.seekIsFirst = this.initialPos
      }
      if (this.seekIsFirst != -1) {
        return this.seekIsFirst
      } else {
        return this.avPlayer.currentTime;
      }

    }
    return 0;
  }

  private setPlayState(playbackState: avSession.AVPlaybackState) {
    if (this.session) {
      this.session.setAVPlaybackState(playbackState, (err: BusinessError) => {
        if (err) {
          console.error(TAG, `SetAVPlaybackState BusinessError: code: ${err.code}, message: ${err.message}`);
        } else {
          console.info(TAG, 'SetAVPlaybackState successfully');
        }
      });
    }
  }
}
