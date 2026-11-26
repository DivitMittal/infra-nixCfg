{
  lib,
  pkgs,
  hostPlatform,
  ...
}: {
  programs.spotify-player = {
    enable = true;
    package =
      if hostPlatform.isDarwin
      then pkgs.custom.spotify-player
      else pkgs.spotify-player;

    settings =
      lib.optionalAttrs hostPlatform.isDarwin {
        # Let the official Spotify app handle audio when Spotify refuses
        # the decryption keys required by the built-in librespot player.
        enable_streaming = "Never";
      }
      // {
        client_id = "561a7e0b6be94efc8f25374180fbe62a";
        login_redirect_uri = "http://127.0.0.1:8989/login";
        enable_media_control = true;
        enable_notify = false;
        enable_cover_image_cache = true;
        cover_img_width = 10;
        cover_img_length = 10;
        cover_img_scale = 2;
        playback_format = "          {status} {track} • {artists}\n          {album}\n          {metadata}";

        device = {
          name = "spotify_player";
          device_type = "L1";
          volume = 100;
          bitrate = 320;
          audio_cache = true;
          normalization = false;
          autoplay = true;
        };
        layout = {
          playback_window_position = "Bottom";
        };
      };

    keymaps = [
      {
        command = "None";
        key_sequence = "q";
      }
    ];
  };
}
