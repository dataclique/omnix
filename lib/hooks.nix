{
  extraHooks ? { },
  rustToolchain ? null,
}:

let
  defaultHooks = {
    nixfmt.enable = true;
    deadnix = {
      enable = true;
      excludes = [ "^templates/" ];
    };
    taplo.enable = true;
  }
  // (
    if rustToolchain != null then
      {
        rustfmt = {
          enable = true;
          entry = "${rustToolchain}/bin/cargo fmt --";
          files = "\\.rs$";
          pass_filenames = true;
        };
      }
    else
      { }
  );

in
defaultHooks // extraHooks
