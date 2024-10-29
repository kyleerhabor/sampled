# Forward

The universal music player.

## Use

> [!NOTE]
>  
> The app is in development with limited feature support. Audio playback, for example, is currently unavailable (you can
> browse metadata, however).

You can either download a release of the app from the [Releases][releases] page or build the project from source in Xcode.

macOS Sequoia (15) or later is required.

### Install

The first time you build the project (as well as for changes to configuration, like building for release), it will take
a significant amount of time to complete.[^1] This is due to the project depending on FFmpeg and libopus.
Subsequent builds should perform much better.

1. Clone the Git repository (e.g. `git clone https://github.com/kyleerhabor/forward Forward`)
2. Open the Xcode project (e.g. `open Forward/Forward.xcodeproj`)
3. Select `Product > Archive` to build the project for release
4. From the Organizer, select `Distribute App > Custom > Copy App` to export the app
5. Open the app 

### Screenshots

<details>
  <summary>Future & Lil Uzi Vert — Pluto x Baby Pluto</summary>
  
  <img src="Documentation/Screenshots/Future & Lil Uzi Vert - Pluto x Baby Pluto.png">
</details>

[^1]: An initial build on my 2019 MacBook Pro takes ~5 minutes to complete. 

[releases]: https://github.com/kyleerhabor/forward/releases
