{ kapack ? import
    (fetchTarball "https://github.com/oar-team/kapack/archive/master.tar.gz")
  {}
, doCoverage ? true
, simgrid ? kapack.simgrid322_2
, batsched ? kapack.batsched_dev
, batexpe ? kapack.batexpe
, pybatsim ? kapack.pybatsim_dev
}:

let
  pkgs = kapack.pkgs;
  pythonPackages = pkgs.python37Packages;
  buildPythonPackage = pythonPackages.buildPythonPackage;

  jobs = rec {
    # Batsim executable binary file.
    batsim = (kapack.batsim.override { simgrid = simgrid; }).overrideAttrs (attr: rec {
      src = pkgs.lib.sourceByRegex ./. [
        "^src"
        "^src/.*\.?pp"
        "^src/unittest"
        "^src/unittest/.*\.?pp"
        "^meson\.build"
      ];
      # Debug build, without any Nix stripping magic.
      mesonBuildType = "debug";
      mesonFlags = []
        ++ pkgs.lib.optional doCoverage [ "-Db_coverage=true" ];
      hardeningDisable = [ "all" ];
      dontStrip = true;

      # Keep files generated by GCOV, so depending jobs can use them.
      postInstall = pkgs.lib.optionalString doCoverage ''
        mkdir -p $out/gcno
        cp batsim@exe/*.gcno $out/gcno/
      '';
    });

    # Batsim integration tests.
    integration_tests = pkgs.stdenv.mkDerivation rec {
      name = "batsim-integration-tests";
      src = pkgs.lib.sourceByRegex ./. [
        "^test"
        "^test/.*\.py"
        "^platforms"
        "^platforms/.*\.xml"
        "^workloads"
        "^workloads/.*\.json"
        "^workloads/smpi"
        "^workloads/smpi/.*"
        "^workloads/smpi/.*/.*\.txt"
        "^events"
        "^events/.*\.txt"
      ];
      buildInputs = with pkgs.python37Packages; [
        batsim batsched batexpe pkgs.redis
        pybatsim pytest pytest_html pandas] ++
      pkgs.lib.optional doCoverage [ gcovr ];

      preBuild = pkgs.lib.optionalString doCoverage ''
        mkdir -p gcda
        export GCOV_PREFIX=$(realpath gcda)
        export GCOV_PREFIX_STRIP=5
      '';
      buildPhase = ''
        runHook preBuild
        set +e
        pytest -ra test/ --html=./report/pytest_report.html
        echo $? > ./pytest_returncode
        set -e
      '';

      checkPhase = ''
        pytest_return_code=$(cat ./pytest_returncode)
        echo "pytest return code: $pytest_return_code"
        if [ $pytest_return_code -ne 0 ] ; then
          exit 1
        fi
      '';
      doCheck = false;

      installPhase = ''
        mkdir -p $out
        mv ./report/* ./pytest_returncode $out/
      '' + pkgs.lib.optionalString doCoverage ''
        mv ./gcda $out/
      '';
    };

    # Batsim doxygen documentation.
    doxydoc = pkgs.stdenv.mkDerivation rec {
      name = "batsim-doxygen-documentation";
      src = pkgs.lib.sourceByRegex ./. [
        "^src"
        "^src/.*\.?pp"
        "^doc"
        "^doc/Doxyfile"
        "^doc/doxygen_mainpage.md"
      ];
      buildInputs = [pkgs.doxygen];
      buildPhase = "(cd doc && doxygen)";
      installPhase = ''
        mkdir -p $out
        mv doc/doxygen_doc/html/* $out/
      '';
      checkPhase = ''
        nb_warnings=$(cat doc/doxygen_warnings.log | wc -l)
        if [[ $nb_warnings -gt 0 ]] ; then
          echo "FAILURE: There are doxygen warnings!"
          cat doc/doxygen_warnings.log
          exit 1
        fi
      '';
      doCheck = true;
    };

    # Batsim sphinx documentation.
    sphinx_doc = pkgs.stdenv.mkDerivation rec {
      name = "batsim-sphinx-documentation";

      src = pkgs.lib.sourceByRegex ./. [
        "^doc"
        "^doc/batsim_rjms_overview.png"
        "^docs"
        "^docs/conf.py"
        "^docs/Makefile"
        "^docs/.*\.bash"
        "^docs/.*\.rst"
        "^docs/img"
        "^docs/img/logo"
        "^docs/img/logo/logo.png"
        "^docs/img/ptask"
        "^docs/img/ptask/CommMatrix.svg"
        "^docs/img/proto"
        "^docs/img/proto/.*\.png"
        "^docs/tuto-first-simulation"
        "^docs/tuto-first-simulation/.*\.bash"
        "^docs/tuto-first-simulation/.*\.rst"
        "^docs/tuto-first-simulation/.*\.out"
        "^docs/tuto-first-simulation/.*\.yaml"
        "^docs/tuto-reproducible-experiment"
        "^docs/tuto-reproducible-experiment/.*\.nix"
        "^docs/tuto-reproducible-experiment/.*\.rst"
        "^docs/tuto-reproducible-experiment/.*\.yaml"
        "^docs/tuto-result-analysis"
        "^docs/tuto-result-analysis/.*\.rst"
        "^docs/tuto-result-analysis/.*\.R"
        "^docs/tuto-sched-implem"
        "^docs/tuto-sched-implem/.*\.rst"
        "^events"
        "^events/test_events_4hosts.txt"
        "^workloads"
        "^workloads/test_various_profile_types.json"
      ];
      buildInputs = with pythonPackages; [ sphinx sphinx_rtd_theme ];

      buildPhase = "cd docs && make html";
      installPhase = ''
        mkdir -p $out
        cp -r _build/html $out/
      '';
    };

    # Dependencies not in nixpkgs as I write these lines.
    pytest_metadata = buildPythonPackage {
      name = "pytest-metadata-1.8.0";
      doCheck = false;
      propagatedBuildInputs = [
        pythonPackages.pytest
      ];
      src = builtins.fetchurl {
        url = "https://files.pythonhosted.org/packages/12/38/eed3a1e00c765e4da61e4e833de41c3458cef5d18e819d09f0f160682993/pytest-metadata-1.8.0.tar.gz";
        sha256 = "1fk6icip2x1nh4kzhbc8cnqrs77avpqvj7ny3xadfh6yhn9aaw90";
      };
    };

    pytest_html = buildPythonPackage {
      name = "pytest-html-1.20.0";
      doCheck = false;
      propagatedBuildInputs = [
        pythonPackages.pytest
        pytest_metadata
      ];
      src = builtins.fetchurl {
        url = "https://files.pythonhosted.org/packages/08/3e/63d998f26c7846d3dac6da152d1b93db3670538c5e2fe18b88690c1f52a7/pytest-html-1.20.0.tar.gz";
        sha256 = "17jyn4czkihrs225nkpj0h113hc03y0cl07myb70jkaykpfmrim7";
      };
    };

    gcovr = buildPythonPackage {
      name = "gcovr-4.1";
      doCheck = false;
      propagatedBuildInputs = [
        pythonPackages.jinja2
      ];
      src = builtins.fetchurl {
        url = "https://files.pythonhosted.org/packages/ed/f2/140298e4696c41fb17e8399166ea73cfe3fb9938faaf814b7e72f8b2e157/gcovr-4.1.tar.gz";
        sha256 = "08hy6vqvq7q7xk0jb9pd5dvjnyxd9x9k0hzcfyqhv9yry8vw756a";
      };
    };
  };
in
  jobs
