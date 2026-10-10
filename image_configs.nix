pkgs: rec {
  # Convinience list of packages.
  base_dev = (with pkgs; [
    procps
    gnugrep
    gnused
    which
    findutils
    iputils
    gnumake
    curl
    bun
    uv
    nano
    git
    bc
    diffutils
    less
    gawk
  ]);

  cpp_packages = with pkgs; [
    cmake
    gcc
    clang
    gnumake
    python3
  ];

  drawing_packages = [ 
    pkgs.plantuml 
    pkgs.d2 
  ];

  editor_packages = [
    pkgs.nano
    pkgs.vim
  ];

  rust_packages = [
    pkgs.rustfmt
    pkgs.rustc
    pkgs.cargo
    pkgs.clippy
  ];

  esp32_packages = [
    pkgs.rustup
    pkgs.llvmPackages.clang-unwrapped
    pkgs.lld
    pkgs.gnutar
    pkgs.gzip
    pkgs.cmake
    pkgs.ninja
    pkgs.pkg-config
    pkgs.gcc
    pkgs.gnumake
    pkgs.python3
    pkgs.git
    pkgs.libxml2
    pkgs.esptool
  ];

  # These end up as 'run' options for nix
  image_specs = {
    docker-nix-minimal.contents = [];
    docker-nix-editor.contents = base_dev ++ editor_packages;
  
    docker-nix-all = {
      contents =
        base_dev
        ++ drawing_packages
        ++ cpp_packages
        ++ editor_packages
        ++ rust_packages
        ++ [ pkgs.mesa
             pkgs.vulkan-loader
             pkgs.opencode ];
    };

    docker-nix-esp = {
      contents =
        base_dev
        ++ esp32_packages
        ++ editor_packages
        ++ rust_packages
        ++ [ pkgs.opencode ];
      nixLdCompat = true;
    };

    docker-nix-opencode = {
      contents =
        base_dev
        ++ [ pkgs.opencode ];
    };
  
    docker-nix-nocargo.contents =
      drawing_packages
      ++ cpp_packages
      ++ editor_packages
      ++ [ pkgs.opencode ];
  
    docker-nix-claude = {
      contents =
        base_dev
        ++ drawing_packages
        ++ cpp_packages
        ++ editor_packages
        ++ rust_packages
        ++ [ pkgs.claude-code ];

      config = { 
        allowUnfree = true; # Needed for 'claude', also need an '--impure' flag at run/build time.
      };
    };
  };
}
