// ignore_for_file: public_member_api_docs

// FOR MORE EXAMPLES, VISIT THE GITHUB REPOSITORY AT:
//
//  https://github.com/ryanheise/audio_service
//
// This example implements a minimal audio handler that renders the current
// media item and playback state to the system notification and responds to 4
// media actions:
//
// - play
// - pause
// - seek
// - stop
//
// To run this example, use:
//
// flutter run

import 'dart:async';
import 'dart:io' as io;
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_service_example/common.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';

// You might want to provide this using dependency injection rather than a
// global variable.
late AudioHandler _audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  final audioPlayerHandler = await AudioPlayerHandler.create();
  _audioHandler = await AudioService.init(
    builder: () => audioPlayerHandler,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.ryanheise.myapp.channel.audio',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: true,
    ),
  );
  _audioHandler.play();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BMW Music',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatelessWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BMW Music'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Show media item title
            StreamBuilder<MediaItem?>(
              stream: _audioHandler.mediaItem,
              builder: (context, snapshot) {
                final mediaItem = snapshot.data;
                return Text(mediaItem?.title ?? '');
              },
            ),
            // Play/pause/stop buttons.
            StreamBuilder<bool>(
              stream: _audioHandler.playbackState
                  .map((state) => state.playing)
                  .distinct(),
              builder: (context, snapshot) {
                final playing = snapshot.data ?? false;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _button(Icons.skip_previous, _audioHandler.skipToPrevious),
                    if (playing)
                      _button(Icons.pause, _audioHandler.pause)
                    else
                      _button(Icons.play_arrow, _audioHandler.play),
                    _button(Icons.stop, _audioHandler.stop),
                    _button(Icons.skip_next, _audioHandler.skipToNext),
                  ],
                );
              },
            ),
            // A seek bar.
            StreamBuilder<MediaState>(
              stream: _mediaStateStream,
              builder: (context, snapshot) {
                final mediaState = snapshot.data;
                return SeekBar(
                  duration: mediaState?.mediaItem?.duration ?? Duration.zero,
                  position: mediaState?.position ?? Duration.zero,
                  onChangeEnd: (newPosition) {
                    _audioHandler.seek(newPosition);
                  },
                );
              },
            ),
            // Display the processing state.
            StreamBuilder<AudioProcessingState>(
              stream: _audioHandler.playbackState
                  .map((state) => state.processingState)
                  .distinct(),
              builder: (context, snapshot) {
                final processingState =
                    snapshot.data ?? AudioProcessingState.idle;
                return Text(
                    "Processing state: ${describeEnum(processingState)}");
              },
            ),
          ],
        ),
      ),
    );
  }

  /// A stream reporting the combined state of the current media item and its
  /// current position.
  Stream<MediaState> get _mediaStateStream =>
      Rx.combineLatest2<MediaItem?, Duration, MediaState>(
          _audioHandler.mediaItem,
          AudioService.position,
          (mediaItem, position) => MediaState(mediaItem, position));

  IconButton _button(IconData iconData, VoidCallback onPressed) => IconButton(
        icon: Icon(iconData),
        iconSize: 64.0,
        onPressed: onPressed,
      );
}

class MediaState {
  final MediaItem? mediaItem;
  final Duration position;

  MediaState(this.mediaItem, this.position);
}

/// An [AudioHandler] for playing a single item.
class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  static int _nextMediaId = 0;

  static Future<List<io.FileSystemEntity>> _listOfFiles() async {
    await Permission.storage.request();
    final fileList =
        io.Directory("/storage/emulated/0/Music/").listSync(recursive: true);
    return fileList
        .where((fileSystemEntity) => fileSystemEntity.path.endsWith('mp3'))
        .toList();
  }

  static Future<ConcatenatingAudioSource> _createPlaylist() async {
    final fileList = await _listOfFiles();
    return ConcatenatingAudioSource(
        children: fileList
            .map((file) => AudioSource.uri(
                  file.uri,
                  tag: MediaItem(
                    id: '${_nextMediaId++}',
                    album: "Music",
                    title: file.path,
                    artUri: Uri.parse(
                        "https://media.wnyc.org/i/1400/1400/l/80/1/ScienceFriday_WNYCStudios_1400.jpg"),
                  ),
                ))
            .toList());
  }

  final _player = AudioPlayer();
  late ConcatenatingAudioSource _playlist;

  /// Initialise our audio handler.
  AudioPlayerHandler() {
    // So that our clients (the Flutter UI and the system notification) know
    // what state to display, here we set up our audio handler to broadcast all
    // playback state changes as they happen via playbackState...
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
  }

  static Future<AudioPlayerHandler> create() async {
    // Load the player.
    final audioPlayerHandler = AudioPlayerHandler();
    audioPlayerHandler._playlist = await _createPlaylist();
    await audioPlayerHandler._player.setAudioSource(audioPlayerHandler._playlist);
    await audioPlayerHandler._player.shuffle();
    await audioPlayerHandler._player.setShuffleModeEnabled(true);
    await audioPlayerHandler._player.setLoopMode(LoopMode.all);
    return audioPlayerHandler;
  }

  // In this simple example, we handle only 4 actions: play, pause, seek and
  // stop. Any button press from the Flutter UI, notification, lock screen or
  // headset will be routed through to these 4 methods so that you can handle
  // your audio playback logic in one place.

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    if (button == MediaButton.previous) {
      await deleteSong();
    }
    await super.click(button);
  }

  Future<void> deleteSong() async {
    print('Deleting song');
    final currentIndex = _player.currentIndex;
    if (currentIndex == null) return;
    final currentSource = _player.sequenceState!.currentSource;
    final path = currentSource!.tag.title as String;

    _player.hasNext == true ? await _player.seekToNext() : await _player.stop();
    // Seek to next again, because we will delete current song from queues
    _player.hasNext == true ? await _player.seekToNext() : await _player.stop();
    await _playlist.removeAt(currentIndex);
    await deleteFile(File(path));
  }

  Future<void> deleteFile(File file) async {
    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (e) {
      print('There was an error while deleting $e');
    }
  }

  /// Transform a just_audio event into an audio_service state.
  ///
  /// This method is used from the constructor. Every event received from the
  /// just_audio player will be transformed into an audio_service state so that
  /// it can be broadcast to audio_service clients.
  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.rewind,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.fastForward,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }
}
