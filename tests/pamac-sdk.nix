# SPDX-License-Identifier: MIT
{ pkgs }:
let
  libpamac = pkgs.stdenv.mkDerivation {
    pname = "libpamac";
    version = "11.7.4";
    src = pkgs.fetchzip {
      url = "https://github.com/manjaro/libpamac/archive/c7efe923f980a3f5966f376bd6d6e6146539a970.tar.gz";
      hash = "sha256-CBZsvyK4KN7ES3/qL7X3+TjwIFG6+UNVRe5t+q0oJGQ=";
    };
    nativeBuildInputs = [
      pkgs.meson
      pkgs.ninja
      pkgs.pkg-config
      pkgs.vala
      pkgs.gobject-introspection
      pkgs.gettext
    ];
    buildInputs = [
      pkgs.glib
      pkgs.json-glib
      pkgs.libsoup_3
      pkgs.polkit
      pkgs.pacman
      pkgs.libarchive
    ];
    mesonFlags = [
      "--sysconfdir=${placeholder "out"}/etc"
      "-Denable-appstream=false"
      "-Denable-aur=true"
    ];
    postInstall = ''
      mkdir -p $out/share/licenses/libpamac
      cp ../COPYING $out/share/licenses/libpamac/
    '';
    meta.license = pkgs.lib.licenses.gpl3Plus;
  };
  pamac = pkgs.stdenv.mkDerivation {
    pname = "pamac-cli";
    version = "11.7.4";
    src = pkgs.fetchzip {
      url = "https://github.com/manjaro/pamac-cli/archive/1ce8a93aeeae71244ecec6d257daae5eea3f3fc4.tar.gz";
      hash = "sha256-j4szcozQ5HnigusX2U0YidpVpLRTfW0qGa5GElsRFXk=";
    };
    nativeBuildInputs = [
      pkgs.meson
      pkgs.ninja
      pkgs.pkg-config
      pkgs.vala
      pkgs.gettext
      pkgs.asciidoc
      pkgs.docbook_xml_dtd_45
      pkgs.docbook_xsl
      pkgs.libxslt
    ];
    mesonFlags = [ "--sysconfdir=${placeholder "out"}/etc" ];
    buildInputs = [
      libpamac
      pkgs.glib
    ];
    postInstall = ''
      mkdir -p $out/share/licenses/pamac-cli
      cp ../COPYING $out/share/licenses/pamac-cli/
    '';
    meta.license = pkgs.lib.licenses.gpl3Plus;
  };
in
{
  inherit libpamac pamac;
}
