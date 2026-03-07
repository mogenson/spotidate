{
  pkgs ? import <nixpkgs> { },
}:

let
  playdate-luacats = pkgs.fetchFromGitHub {
    owner = "notpeter";
    repo = "playdate-luacats";
    rev = "76d5661c8e72207e055e7c6d34f7296c0736d0f1";
    sha256 = "sha256-ajDHuCzC/82NxEJazsBaeD9R3gpW5Ek09Q5xOg4K/OA=";
  };

  lua-utils = pkgs.fetchFromGitHub {
    owner = "mogenson";
    repo = "lua-utils";
    rev = "90455b4c79fe61322ff50c403a2555cefd12a0fd";
    sha256 = "sha256-ktXDtw75MZswnQImz5PQ+ihqSepIUwD+j+PVKVEpCFA=";
  };

in
pkgs.mkShell {
  shellHook = ''
    ln -sf ${playdate-luacats}/library/stub.lua definitions/stub.lua
    ln -sf ${lua-utils}/async.lua src/async.lua
  '';
}
