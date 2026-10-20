@echo off
REM ============================================================================
REM install.bat - Agentic AI Instruction Framework installer
REM ============================================================================
REM Installs common instructions and configurations into each workspace.
REM Sets up .claude and/or .github folders with shared agent definitions,
REM skills, and customization files across the workspace.
REM
REM Also applies overlay source directories for team-specific configurations
REM and customizations. Sources may be existing directories or Git-backed
REM repositories cloned and updated by the installer.
REM
REM Usage:
REM  install.bat
REM  install.bat --workspace <name>
REM  install.bat --workspace <name> --repo <name>
REM  install.bat --backup
REM  install.bat --purge
REM  install.bat --purge-all
REM  install.bat --keep-arch
REM  install.bat --skip-claude
REM  install.bat --local <path> [--workspace <name> [--repo <name>]]
REM  install.bat overlay add <name> (--url <url> [--branch <branch>] [--path <path>] / --path <existing-source>) [--verbose] [--workspace <name>]
REM  install.bat overlay update <name> [--path <path>] [--verbose] [--workspace <name>]
REM  install.bat overlay remove <name> [--path <path>]
REM  install.bat --help
REM  install.bat -h
REM  install.bat ?
REM ============================================================================
setlocal EnableExtensions DisableDelayedExpansion

REM --- Determine repo root early so it is available in all control-flow blocks
set "REPO_ROOT=%~dp0"
set "REPO_ROOT_ARG=%REPO_ROOT%"
if "%REPO_ROOT_ARG:~-1%"=="\" set "REPO_ROOT_ARG=%REPO_ROOT_ARG:~0,-1%"

REM --- Initialize variables
set "OVERLAY_REPO_URL="
set "OVERLAY_BRANCH=develop"
set "OVERLAY_PATH_IN="
set "OVERLAY_PATH_DEFAULTED="
set "VERBOSE_FLAG="
set "SKIP_WORKSPACE="
set "SKIP_OVERLAY="
set "OVERLAY_ACTION="
set "OVERLAY_NAME="
set "WORKSPACE_NAME="
set "REPO_NAME="
set "BACKUP_WORKSPACE="
set "PURGE_WORKSPACE="
set "PURGE_ALL_BACKUPS="
set "KEEP_ARCHITECTURE="
set "SKIP_CLAUDE="
set "WORKSPACE_SETUP_FLAGS="
set "OVERLAY_BRANCH_SET="
set "OVERLAY_URL_PROMPTED="
set "LOCAL_ACTION="
set "LOCAL_PATH_IN="
set "TARGET_BASE=<WORKSPACE_PROJECTS_ROOT>"

REM --- Capture the directory install.bat was invoked from, before pushd changes
REM     it, so a relative --local path still resolves against the caller's cwd.
set "INVOKE_CWD=%CD%"

REM --- Verify the framework payload exists next to install.bat (the source root),
REM     so install.bat can run from a local clone OR the shared folder that holds it.
REM     Skipped for help so --help works from anywhere.
set "SKIP_SRC_CHECK="
if /i "%~1"=="--help" set "SKIP_SRC_CHECK=1"
if /i "%~1"=="-h" set "SKIP_SRC_CHECK=1"
if "%~1"=="?" set "SKIP_SRC_CHECK=1"
if not defined SKIP_SRC_CHECK if not exist "%REPO_ROOT%scripts\setup-workspace.ps1" (
    echo ERROR: Framework files were not found next to install.bat.
    echo Expected: %REPO_ROOT%scripts\setup-workspace.ps1
    echo Run install.bat from the framework root ^(a local clone or the shared folder that contains it^).
    exit /b 2
)
if not defined SKIP_SRC_CHECK if not exist "%REPO_ROOT%base\README.md" (
    echo ERROR: Framework base payload was not found next to install.bat.
    echo Expected: %REPO_ROOT%base\README.md
    echo Restore the complete framework source before installing.
    exit /b 2
)
if not defined SKIP_SRC_CHECK if not exist "%REPO_ROOT%base\copilot-instructions.md" (
    echo ERROR: Framework base payload is incomplete.
    echo Expected: %REPO_ROOT%base\copilot-instructions.md
    echo Restore the complete framework source before installing.
    exit /b 2
)
if not defined SKIP_SRC_CHECK if not exist "%REPO_ROOT%base\config\default-config.yaml" (
    echo ERROR: Framework protected base config is incomplete.
    echo Expected: %REPO_ROOT%base\config\default-config.yaml
    echo Restore the complete framework source before installing.
    exit /b 2
)
if not defined SKIP_SRC_CHECK if not exist "%REPO_ROOT%base\config\guardrails.yaml" (
    echo ERROR: Framework protected base config is incomplete.
    echo Expected: %REPO_ROOT%base\config\guardrails.yaml
    echo Restore the complete framework source before installing.
    exit /b 2
)

REM --- Use the install.bat directory as the working directory. pushd maps a
REM     temporary drive for UNC paths, so install.bat also runs directly from a
REM     shared folder. The whole run is wrapped in a call so popd always runs on exit.
pushd "%REPO_ROOT_ARG%" 2>nul
call :run %*
set "INSTALL_RC=%ERRORLEVEL%"
popd 2>nul
exit /b %INSTALL_RC%

:run

REM --- Preserve the first required setup failure while allowing independent
REM     requested steps to finish and report their own outcomes.
set "RUN_RC=0"

REM --- Parse command-line arguments
:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="--help" goto show_help
if /i "%~1"=="-h" goto show_help
if "%~1"=="?" goto show_help
if /i "%~1"=="overlay" (
    if "%~2"=="" (
        echo ERROR: overlay requires an action: add, update, or remove
        exit /b 1
    )
    if /i not "%~2"=="add" if /i not "%~2"=="update" if /i not "%~2"=="remove" (
        echo ERROR: Invalid overlay action: %~2. Expected add, update, or remove.
        exit /b 1
    )
    if "%~3"=="" (
        echo ERROR: overlay %~2 requires an overlay name
        exit /b 1
    )
    set "OVERLAY_ACTION=%~2"
    set "OVERLAY_NAME=%~3"
    shift
    shift
    shift
    goto parse_args
)
if /i "%~1"=="--url" (
    if /i not "%OVERLAY_ACTION%"=="add" (
        echo ERROR: --url is only supported with 'overlay add'.
        echo Example: install.bat overlay add my-workspace --url ^<ssh-url-of-overlay-repo^>
        exit /b 1
    )
    if "%~2"=="" (
        echo ERROR: --url requires a repository URL
        exit /b 1
    )
    set "OVERLAY_REPO_URL=%~2"
    shift
    shift
    goto parse_args
)
if /i "%~1"=="--branch" (
    if /i not "%OVERLAY_ACTION%"=="add" (
        echo ERROR: --branch is only supported with 'overlay add'.
        echo Example: install.bat overlay add my-workspace --url ^<ssh-url-of-overlay-repo^> --branch develop
        exit /b 1
    )
    if "%~2"=="" (
        echo ERROR: --branch requires a branch name
        exit /b 1
    )
    set "OVERLAY_BRANCH=%~2"
    set "OVERLAY_BRANCH_SET=1"
    shift
    shift
    goto parse_args
)
if /i "%~1"=="--path" (
    if "%OVERLAY_ACTION%"=="" (
        echo ERROR: --path is only supported with 'overlay add', 'overlay update' or 'overlay remove'.
        echo Example: install.bat overlay add my-workspace --url ^<ssh-url-of-overlay-repo^> --path <FRAMEWORK_HOME>\overlays\my-workspace
        exit /b 1
    )
    if "%~2"=="" (
        echo ERROR: --path requires a directory path
        exit /b 1
    )
    set "OVERLAY_PATH_IN=%~2"
    shift
    shift
    goto parse_args
)
if /i "%~1"=="--verbose" (
    set "VERBOSE_FLAG=-Verbose"
    shift
    goto parse_args
)
if /i "%~1"=="--skip-workspace" (
    set "SKIP_WORKSPACE=1"
    shift
    goto parse_args
)
if /i "%~1"=="--skip-overlay" (
    set "SKIP_OVERLAY=1"
    shift
    goto parse_args
)
if /i "%~1"=="--workspace" (
    if "%~2"=="" (
        echo ERROR: --workspace requires a workspace name argument
        exit /b 1
    )
    set "WORKSPACE_NAME=%~2"
    shift
    shift
    goto parse_args
)
if /i "%~1"=="--repo" (
    if "%~2"=="" (
        echo ERROR: --repo requires a repository name argument
        exit /b 1
    )
    set "REPO_NAME=%~2"
    shift
    shift
    goto parse_args
)
if /i "%~1"=="--backup" (
    set "BACKUP_WORKSPACE=1"
    shift
    goto parse_args
)
if /i "%~1"=="--purge" (
    set "PURGE_WORKSPACE=1"
    shift
    goto parse_args
)
if /i "%~1"=="--purge-all" (
    set "PURGE_ALL_BACKUPS=1"
    shift
    goto parse_args
)
if /i "%~1"=="--keep-arch" (
    set "KEEP_ARCHITECTURE=1"
    shift
    goto parse_args
)
if /i "%~1"=="--skip-claude" (
    set "SKIP_CLAUDE=1"
    shift
    goto parse_args
)
if /i "%~1"=="--local" goto parse_local
echo ERROR: Unknown argument: %~1
echo Run install.bat --help for supported options.
exit /b 1

:parse_local
set "LOCAL_ACTION=1"
set "LOCAL_NEXT=%~2"
if not defined LOCAL_NEXT goto parse_local_done
set "LOCAL_TAKE_VAL=1"
if "%LOCAL_NEXT:~0,1%"=="-" set "LOCAL_TAKE_VAL="
if /i "%LOCAL_NEXT%"=="overlay" set "LOCAL_TAKE_VAL="
if not defined LOCAL_TAKE_VAL goto parse_local_done
set "LOCAL_PATH_IN=%~2"
shift
:parse_local_done
shift
goto parse_args

:args_done
setlocal EnableDelayedExpansion

if defined OVERLAY_ACTION (
    powershell.exe -NoProfile -Command "$n=$env:OVERLAY_NAME; if ($n -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $n -in @('.', '..')) { exit 1 }"
    if errorlevel 1 (
        echo ERROR: overlay name must be one safe path segment using letters, numbers, dot, underscore, or hyphen.
        exit /b 1
    )
)

if not "!REPO_NAME!"=="" if "!WORKSPACE_NAME!"=="" (
    echo ERROR: --repo can only be used together with --workspace
    exit /b 1
)

if "%LOCAL_ACTION%"=="1" if /i "%OVERLAY_ACTION%"=="update" (
    echo ERROR: --local cannot be combined with 'overlay update'.
    exit /b 1
)
if "%LOCAL_ACTION%"=="1" if /i "%OVERLAY_ACTION%"=="remove" (
    echo ERROR: --local cannot be combined with 'overlay remove'.
    exit /b 1
)

if "%BACKUP_WORKSPACE%"=="1" if "%PURGE_WORKSPACE%"=="1" (
    echo ERROR: --backup and --purge cannot be used together
    exit /b 1
)

if "%BACKUP_WORKSPACE%"=="1" if "%PURGE_ALL_BACKUPS%"=="1" (
    echo ERROR: --backup and --purge-all cannot be used together
    exit /b 1
)

if "%PURGE_WORKSPACE%"=="1" if "%PURGE_ALL_BACKUPS%"=="1" (
    echo ERROR: --purge and --purge-all cannot be used together
    exit /b 1
)

if "%KEEP_ARCHITECTURE%"=="1" if "%BACKUP_WORKSPACE%"=="1" (
    echo ERROR: --keep-arch cannot be used with --backup.
    exit /b 1
)

if "%KEEP_ARCHITECTURE%"=="1" if "%PURGE_WORKSPACE%"=="1" (
    echo ERROR: --keep-arch cannot be used with --purge.
    exit /b 1
)

if "%KEEP_ARCHITECTURE%"=="1" if "%PURGE_ALL_BACKUPS%"=="1" (
    echo ERROR: --keep-arch cannot be used with --purge-all.
    exit /b 1
)

if "%SKIP_WORKSPACE%"=="1" if "%BACKUP_WORKSPACE%"=="1" (
    echo ERROR: --backup can only be used when workspace setup runs.
    echo Remove --skip-workspace or remove --backup.
    exit /b 1
)

if "%SKIP_WORKSPACE%"=="1" if "%PURGE_WORKSPACE%"=="1" (
    echo ERROR: --purge can only be used when workspace setup runs.
    echo Remove --skip-workspace or remove --purge.
    exit /b 1
)

if "%SKIP_WORKSPACE%"=="1" if "%PURGE_ALL_BACKUPS%"=="1" (
    echo ERROR: --purge-all can only be used when workspace setup runs.
    echo Remove --skip-workspace or remove --purge-all.
    exit /b 1
)

if "%SKIP_WORKSPACE%"=="1" if "%KEEP_ARCHITECTURE%"=="1" (
    echo ERROR: --keep-arch can only be used when workspace setup runs.
    echo Remove --skip-workspace or remove --keep-arch.
    exit /b 1
)

if /i "%OVERLAY_ACTION%"=="update" if "%BACKUP_WORKSPACE%"=="1" (
    echo ERROR: --backup is not an overlay update option.
    echo Use it with workspace setup commands only.
    exit /b 1
)

if /i "%OVERLAY_ACTION%"=="update" if "%PURGE_WORKSPACE%"=="1" (
    echo ERROR: --purge is not an overlay update option.
    echo Use it with workspace setup commands only.
    exit /b 1
)

if /i "%OVERLAY_ACTION%"=="update" if "%PURGE_ALL_BACKUPS%"=="1" (
    echo ERROR: --purge-all is not an overlay update option.
    echo Use it with workspace setup commands only.
    exit /b 1
)

if /i "%OVERLAY_ACTION%"=="update" if "%KEEP_ARCHITECTURE%"=="1" (
    echo ERROR: --keep-arch is not an overlay update option.
    echo Use it with workspace setup commands only.
    exit /b 1
)

if /i "%OVERLAY_ACTION%"=="remove" if "%BACKUP_WORKSPACE%"=="1" (
    echo ERROR: --backup is not an overlay remove option.
    echo Use it with workspace setup commands only.
    exit /b 1
)

if /i "%OVERLAY_ACTION%"=="remove" if "%PURGE_WORKSPACE%"=="1" (
    echo ERROR: --purge is not an overlay remove option.
    echo Use it with workspace setup commands only.
    exit /b 1
)

if /i "%OVERLAY_ACTION%"=="remove" if "%PURGE_ALL_BACKUPS%"=="1" (
    echo ERROR: --purge-all is not an overlay remove option.
    echo Use it with workspace setup commands only.
    exit /b 1
)

if /i "%OVERLAY_ACTION%"=="remove" if "%KEEP_ARCHITECTURE%"=="1" (
    echo ERROR: --keep-arch is not an overlay remove option.
    echo Use it with workspace setup commands only.
    exit /b 1
)

if "%BACKUP_WORKSPACE%"=="1" set "WORKSPACE_SETUP_FLAGS=!WORKSPACE_SETUP_FLAGS! -BackupWorkspace"
if "%PURGE_WORKSPACE%"=="1" set "WORKSPACE_SETUP_FLAGS=!WORKSPACE_SETUP_FLAGS! -PurgeWorkspace"
if "%PURGE_ALL_BACKUPS%"=="1" set "WORKSPACE_SETUP_FLAGS=!WORKSPACE_SETUP_FLAGS! -PurgeAllBackups"
if "%KEEP_ARCHITECTURE%"=="1" set "WORKSPACE_SETUP_FLAGS=!WORKSPACE_SETUP_FLAGS! -KeepArchitecture"
if "%SKIP_CLAUDE%"=="1" set "WORKSPACE_SETUP_FLAGS=!WORKSPACE_SETUP_FLAGS! -SkipClaude"
REM Export --skip-claude for setup-overlay.ps1 (many call sites) via env var,
REM mirroring the AI_LOCAL_TIER pattern, so the overlay mirror is skipped too.
if "%SKIP_CLAUDE%"=="1" set "AI_SKIP_CLAUDE=1"

REM --- Handle overlay actions (add/remove)
if /i "%OVERLAY_ACTION%"=="add" (
    if "%OVERLAY_NAME%"=="" (
        echo ERROR: overlay name is required for 'overlay add'
        exit /b 1
    )
    if "%SKIP_OVERLAY%"=="1" (
        echo ERROR: --skip-overlay cannot be combined with 'overlay add'.
        exit /b 1
    )
    if "!OVERLAY_REPO_URL!"=="" if "!OVERLAY_PATH_IN!"=="" (
        echo ERROR: 'overlay add' requires either --url ^<repository-url^> or --path ^<existing-overlay-source^>.
        exit /b 1
    )
    if "!OVERLAY_REPO_URL!"=="" if "!OVERLAY_BRANCH_SET!"=="1" (
        echo ERROR: --branch requires --url because an existing path is not cloned.
        exit /b 1
    )
    if "!OVERLAY_REPO_URL!"=="" if not exist "!OVERLAY_PATH_IN!" (
        echo ERROR: Existing overlay source path does not exist: !OVERLAY_PATH_IN!
        exit /b 1
    )
    REM Set the default clone path only for a URL-backed source.
    if not "!OVERLAY_REPO_URL!"=="" if "!OVERLAY_PATH_IN!"=="" (
        set "OVERLAY_PATH_IN=<FRAMEWORK_HOME>\overlays\%OVERLAY_NAME%"
    )
    REM Continue with normal flow (workspace setup + overlay add)
    REM Unless --skip-workspace was explicitly provided, workspace setup will run
    goto main_flow
)

if /i "%OVERLAY_ACTION%"=="update" (
    if "%OVERLAY_NAME%"=="" (
        echo ERROR: overlay name is required for 'overlay update'
        exit /b 1
    )
    if "!OVERLAY_PATH_IN!"=="" (
        set "OVERLAY_PATH_IN=<FRAMEWORK_HOME>\overlays\%OVERLAY_NAME%"
        set "OVERLAY_PATH_DEFAULTED=1"
    )
    goto update_overlay
)

if /i "%OVERLAY_ACTION%"=="remove" (
    if "%OVERLAY_NAME%"=="" (
        echo ERROR: overlay name is required for 'overlay remove'
        exit /b 1
    )
    REM Default path to remove
    if "!OVERLAY_PATH_IN!"=="" (
        set "OVERLAY_PATH_IN=<FRAMEWORK_HOME>\overlays\%OVERLAY_NAME%"
        set "OVERLAY_PATH_DEFAULTED=1"
    )
    goto remove_overlay
)

:main_flow

echo.
echo ============================================================
echo Agentic AI Instruction Framework Installer
echo ============================================================
echo.
echo This installer sets up common instructions and configurations
echo within your workspace. It will install shared agent definitions,
echo skills, and customization files to .claude and/or .github folders.
echo.

REM --- Resolve the local overlay tier (set by --local). Applied as the final
REM     overwrite by setup-workspace.ps1 and setup-overlay.ps1 via AI_LOCAL_TIER.
if "%LOCAL_ACTION%"=="1" (
    call :ResolveLocalTier
    if defined AI_LOCAL_TIER (
        echo Local overlay tier will be applied from: !AI_LOCAL_TIER!
    ) else (
        echo Skipping local overlay tier.
    )
)

REM --- Step 1: Run workspace setup script (unless skipped)
if "%SKIP_WORKSPACE%"=="1" (
    echo Skipping workspace setup due to --skip-workspace.
) else (
    set "SETUP_SCRIPT=!REPO_ROOT!scripts\setup-workspace.ps1"
    echo.
    echo Running workspace setup ...
    if not exist "!SETUP_SCRIPT!" (
        echo ERROR: Workspace setup script not found at: !SETUP_SCRIPT!
        exit /b 2
    )

    if "!WORKSPACE_NAME!"=="" (
        echo Invoking setup-workspace for all workspaces.
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!SETUP_SCRIPT!" -RepoRoot "!REPO_ROOT_ARG!" -BasePath "%TARGET_BASE%" !WORKSPACE_SETUP_FLAGS!
    ) else (
        if "!REPO_NAME!"=="" (
            echo Invoking setup-workspace with -WorkspaceName "!WORKSPACE_NAME!".
            powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!SETUP_SCRIPT!" -RepoRoot "!REPO_ROOT_ARG!" -BasePath "%TARGET_BASE%" -WorkspaceName "!WORKSPACE_NAME!" !WORKSPACE_SETUP_FLAGS!
        ) else (
            echo Invoking setup-workspace with -WorkspaceName "!WORKSPACE_NAME!" -RepoName "!REPO_NAME!".
            powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!SETUP_SCRIPT!" -RepoRoot "!REPO_ROOT_ARG!" -BasePath "%TARGET_BASE%" -WorkspaceName "!WORKSPACE_NAME!" -RepoName "!REPO_NAME!" !WORKSPACE_SETUP_FLAGS!
        )
    )
    set "WORKSPACE_SETUP_RC=!ERRORLEVEL!"
    if not "!WORKSPACE_SETUP_RC!"=="0" (
        echo ERROR: Workspace setup script encountered an error. Exit code: !WORKSPACE_SETUP_RC!
        if "!RUN_RC!"=="0" set "RUN_RC=!WORKSPACE_SETUP_RC!"
    )
)

REM --- Step 2: Resolve and apply the overlay source (unless skipped)
if "%SKIP_OVERLAY%"=="1" (
    echo.
    echo Skipping overlay source resolution due to --skip-overlay.
) else (
    REM --- If neither an existing source path nor a URL was provided, ask interactively.
    if "!OVERLAY_REPO_URL!"=="" if "!OVERLAY_PATH_IN!"=="" (
        echo.
        echo.
        set "OVERLAY_URL_PROMPTED=1"
        set /p "OVERLAY_REPO_URL=overlay repository URL (leave blank to skip): "
    )

    if "!OVERLAY_REPO_URL!"=="" if "!OVERLAY_PATH_IN!"=="" (
        echo.
        echo Skipping overlay source.
    ) else (
        REM --- If URL was entered interactively and --branch was not provided, ask for branch (default: develop)
        if "!OVERLAY_URL_PROMPTED!"=="1" if not "!OVERLAY_BRANCH_SET!"=="1" (
            set "OVERLAY_BRANCH_INPUT="
            echo Leave blank to use develop.
            set /p "OVERLAY_BRANCH_INPUT=Overlay branch [!OVERLAY_BRANCH!]: "
            if not "!OVERLAY_BRANCH_INPUT!"=="" set "OVERLAY_BRANCH=!OVERLAY_BRANCH_INPUT!"
        )
        
        REM --- If overlay path was not provided via parameter, ask interactively
        if "!OVERLAY_PATH_IN!"=="" (
            if "!OVERLAY_NAME!"=="" (
                set /p "OVERLAY_NAME=Overlay alias (used for the local clone directory): "
                if "!OVERLAY_NAME!"=="" (
                    echo ERROR: overlay alias is required when a repository URL is entered interactively.
                    exit /b 1
                )
                powershell.exe -NoProfile -Command "$n=$env:OVERLAY_NAME; if ($n -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $n -in @('.', '..')) { exit 1 }"
                if errorlevel 1 (
                    echo ERROR: overlay name must be one safe path segment using letters, numbers, dot, underscore, or hyphen.
                    exit /b 1
                )
            )
            set "DEFAULT_OVERLAY_PATH=<FRAMEWORK_HOME>\overlays\!OVERLAY_NAME!"
            set /p "OVERLAY_PATH_IN=Overlay destination path [!DEFAULT_OVERLAY_PATH!]: "
            if "!OVERLAY_PATH_IN!"=="" set "OVERLAY_PATH_IN=!DEFAULT_OVERLAY_PATH!"
        )

        echo.
        set "SKIP_OVERLAY_CLONE=0"
        if "!OVERLAY_REPO_URL!"=="" (
            if not exist "!OVERLAY_PATH_IN!\overlays" (
                echo ERROR: Standalone overlay source must contain an overlays directory: !OVERLAY_PATH_IN!
                exit /b 1
            )
            echo Using standalone overlay source at "!OVERLAY_PATH_IN!"; no Git command will run.
            set "SKIP_OVERLAY_CLONE=1"
        )

        if "!SKIP_OVERLAY_CLONE!"=="0" (
            echo Preparing overlay repository ...
            echo Repository URL: configured ^(credentials hidden^)
            echo Destination: !OVERLAY_PATH_IN!
            echo Branch: !OVERLAY_BRANCH!
            set "CLONE_SCRIPT=!REPO_ROOT!scripts\clone-bitbucket-repo.ps1"

            if not exist "!CLONE_SCRIPT!" (
                echo ERROR: Clone script not found at: !CLONE_SCRIPT!
                exit /b 2
            )

            REM --- Clone a missing destination or validate/update an existing checkout.
            powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!CLONE_SCRIPT!" ^
              -RepoUrl "!OVERLAY_REPO_URL!" ^
              -DestinationPath "!OVERLAY_PATH_IN!" ^
              -Branch "!OVERLAY_BRANCH!" %VERBOSE_FLAG%
            set "CLONE_RC=!ERRORLEVEL!"

            if not "!CLONE_RC!"=="0" (
                echo WARNING: Overlay repository clone/update encountered an error. Exit code: !CLONE_RC!
                echo You can retry later by running the clone script directly:
                echo   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!CLONE_SCRIPT!" -RepoUrl "^<repository-url^>" -DestinationPath "!OVERLAY_PATH_IN!" -Branch "!OVERLAY_BRANCH!" %VERBOSE_FLAG%
                if "!RUN_RC!"=="0" set "RUN_RC=!CLONE_RC!"
                goto main_done
            )
            echo.
            echo Overlay repository is ready at: !OVERLAY_PATH_IN!
            echo.
        )

        echo Running overlay setup to copy files to workspace .github directories ...
        set "POST_SETUP_SCRIPT=!REPO_ROOT!scripts\setup-overlay.ps1"
        if "!WORKSPACE_NAME!"=="" (
            powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!POST_SETUP_SCRIPT!" -OverlayPath "!OVERLAY_PATH_IN!" -BasePath "%TARGET_BASE%" %VERBOSE_FLAG%
        ) else (
            if "!REPO_NAME!"=="" (
                powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!POST_SETUP_SCRIPT!" -OverlayPath "!OVERLAY_PATH_IN!" -BasePath "%TARGET_BASE%" -WorkspaceName "!WORKSPACE_NAME!" %VERBOSE_FLAG%
            ) else (
                powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!POST_SETUP_SCRIPT!" -OverlayPath "!OVERLAY_PATH_IN!" -BasePath "%TARGET_BASE%" -WorkspaceName "!WORKSPACE_NAME!" -RepoName "!REPO_NAME!" %VERBOSE_FLAG%
            )
        )
        set "POST_SETUP_RC=!ERRORLEVEL!"
        if not "!POST_SETUP_RC!"=="0" (
            echo ERROR: Overlay setup failed. Exit code: !POST_SETUP_RC!
            if "!RUN_RC!"=="0" set "RUN_RC=!POST_SETUP_RC!"
        )
    )
)

:main_done

echo.
echo ============================================================
if "!RUN_RC!"=="0" (
    echo Agentic AI Instruction Framework setup complete.
) else (
    echo Agentic AI Instruction Framework setup incomplete. One or more required steps failed.
)
echo ============================================================
echo.
exit /b !RUN_RC!

REM ============================================================================
REM Update overlay section
REM ============================================================================
:update_overlay
echo.
echo Updating overlay: %OVERLAY_NAME%
echo Path: !OVERLAY_PATH_IN!
if "%OVERLAY_PATH_DEFAULTED%"=="1" (
    echo NOTE: --path was not provided, so the default overlay source path is being used.
    echo       Custom source paths are not remembered; repeat --path for an overlay added elsewhere.
)

if not exist "!OVERLAY_PATH_IN!" (
    echo.
    echo ERROR: Overlay path does not exist: !OVERLAY_PATH_IN!
    if "%OVERLAY_PATH_DEFAULTED%"=="1" (
        echo If this overlay was added with a custom path, run:
        echo   install.bat overlay update %OVERLAY_NAME% --path ^<custom-path^>
    )
    exit /b 1
)

if exist "!OVERLAY_PATH_IN!\.git" (
    echo Running git pull --rebase ...
    set "UPDATE_SCRIPT=!REPO_ROOT!scripts\clone-bitbucket-repo.ps1"
    if not exist "!UPDATE_SCRIPT!" (
        echo ERROR: Git update helper not found at: !UPDATE_SCRIPT!
        exit /b 2
    )
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!UPDATE_SCRIPT!" ^
      -UpdateOnly -DestinationPath "!OVERLAY_PATH_IN!"
    if errorlevel 1 (
        echo ERROR: Failed to update overlay repository.
        exit /b 1
    )
) else (
    if not exist "!OVERLAY_PATH_IN!\overlays\" (
        echo ERROR: Overlay source path must contain an overlays directory: !OVERLAY_PATH_IN!
        exit /b 1
    )
    echo Overlay source is not Git-backed; skipping pull and reapplying current files.
)

echo Overlay %OVERLAY_NAME% source is ready.
echo.
echo Running overlay setup to copy files to workspace .github directories ...
set "POST_SETUP_SCRIPT=!REPO_ROOT!scripts\setup-overlay.ps1"
if "!WORKSPACE_NAME!"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!POST_SETUP_SCRIPT!" -OverlayPath "!OVERLAY_PATH_IN!" -BasePath "%TARGET_BASE%" %VERBOSE_FLAG%
) else (
    if "!REPO_NAME!"=="" (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!POST_SETUP_SCRIPT!" -OverlayPath "!OVERLAY_PATH_IN!" -BasePath "%TARGET_BASE%" -WorkspaceName "!WORKSPACE_NAME!" %VERBOSE_FLAG%
    ) else (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "!POST_SETUP_SCRIPT!" -OverlayPath "!OVERLAY_PATH_IN!" -BasePath "%TARGET_BASE%" -WorkspaceName "!WORKSPACE_NAME!" -RepoName "!REPO_NAME!" %VERBOSE_FLAG%
    )
)
set "POST_SETUP_RC=!ERRORLEVEL!"
if not "!POST_SETUP_RC!"=="0" (
    echo ERROR: Overlay source was refreshed, but overlay setup failed. Exit code: !POST_SETUP_RC!
    exit /b !POST_SETUP_RC!
)
exit /b 0

REM ============================================================================
REM Remove overlay section
REM ============================================================================
:remove_overlay
echo.
echo Removing overlay: %OVERLAY_NAME%
echo Path: !OVERLAY_PATH_IN!
if "%OVERLAY_PATH_DEFAULTED%"=="1" (
    echo NOTE: --path was not provided, so the default overlay source path is being used.
    echo       Custom source paths are not remembered; repeat --path for an overlay added elsewhere.
)

if not exist "!OVERLAY_PATH_IN!" (
    echo.
    echo Overlay path does not exist: !OVERLAY_PATH_IN!
    if "%OVERLAY_PATH_DEFAULTED%"=="1" (
        echo If this overlay was added with a custom path, run:
        echo   install.bat overlay remove %OVERLAY_NAME% --path ^<custom-path^>
        exit /b 1
    )
    echo Nothing to remove.
    exit /b 0
)

REM Reject protected roots and require an overlays/ marker before recursive deletion.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$p=[IO.Path]::GetFullPath($env:OVERLAY_PATH_IN).TrimEnd([char]92); $drive=[IO.Path]::GetPathRoot($p).TrimEnd([char]92); $projects=[IO.Path]::GetFullPath($env:TARGET_BASE).TrimEnd([char]92); if ([string]::IsNullOrWhiteSpace($p) -or $p -eq $drive -or $p -eq $projects) { exit 1 }; if ($p -notmatch '(^|\\)overlays(\\|$)') { exit 2 }; exit 0"
set "REMOVE_VALIDATION_RC=%ERRORLEVEL%"
if "%REMOVE_VALIDATION_RC%"=="1" (
    echo ERROR: Refusing to remove a protected filesystem, workspace, or framework path.
    exit /b 1
)
if "%REMOVE_VALIDATION_RC%"=="2" (
    echo ERROR: Refusing to remove a directory that is not an overlay source ^(requires overlays\^).
    exit /b 1
)
if not "%REMOVE_VALIDATION_RC%"=="0" (
    echo ERROR: Could not validate the overlay removal path.
    exit /b 1
)

echo.
set /p "CONFIRM=Are you sure you want to remove !OVERLAY_PATH_IN!? (y/n): "
if /i not "%CONFIRM%"=="y" (
    echo Removal cancelled.
    exit /b 0
)

REM Remove the directory
echo Removing directory...
rmdir /s /q "!OVERLAY_PATH_IN!"
if errorlevel 1 (
    echo ERROR: Failed to remove overlay directory
    exit /b 1
)

echo Overlay %OVERLAY_NAME% removed successfully.
exit /b 0

REM ============================================================================
REM Help section
REM ============================================================================
:show_help
echo.
echo Agentic AI Instruction Framework Installer
echo.
echo Usage:
echo   install.bat                                    Interactive mode
echo   install.bat --workspace ^<name^> [--backup^|--purge^|--purge-all^|--keep-arch]  Setup only the specified workspace
echo   install.bat --workspace ^<name^> --repo ^<name^> [--backup^|--purge^|--purge-all^|--keep-arch]  Setup only the specified repository path under workspace
echo   install.bat overlay add ^<name^> [options]        Clone and apply a Git-backed overlay
echo   install.bat overlay add ^<name^> --path ^<existing-source^> [options]  Apply an existing overlay source
echo   install.bat overlay update ^<name^> [options]      Pull when Git-backed, then reapply
echo   install.bat overlay update ^<name^> --workspace ^<name^>  Refresh/reapply to one workspace
echo   install.bat overlay remove ^<name^> [--path ^<path^>]  Delete an overlay source directory
echo   install.bat --local ^<path^> [--workspace ^<name^> [--repo ^<name^>]]  Apply local overlay tier (overwrite)
echo   install.bat --help^|-h^|?                          Show this help
echo.
echo Workspace Setup Options:
echo   --backup          Backup existing .github/.claude/CLAUDE.md to .github.bak/.claude.bak/CLAUDE.md.bak ^(rotating backups^)
echo   --purge           Remove existing .github/.claude/CLAUDE.md before recreating
echo   --purge-all       Delete existing .github/.claude/CLAUDE.md AND all backups ^(.github.bak*, .claude.bak*, CLAUDE.md.bak*^)
echo   --keep-arch       Keep existing .github/copilot-instructions.md and copilot-infra-nutshell.md during the base copy
echo   --skip-claude     Install the Copilot .github layout only ^(skip the .claude/CLAUDE.md mirror^); --backup/--purge apply to .github only
echo   --workspace ^<name^>  Setup only the specified workspace (default: all workspaces)
echo   --repo ^<name^>     Optional target repository under --workspace (e.g. workspace\repo)
echo.
echo Overlay Options:
echo   --url ^<url^>       Optional overlay repository URL to clone ^(overlay add only^)
echo   --branch ^<branch^>  Git branch to clone; requires --url ^(default: develop^)
echo   --path ^<path^>     Existing overlay source or clone destination; repeat for update/remove
echo   --verbose         Enable verbose logging for overlay clone/setup (any mode)
echo   --skip-workspace  Skip workspace setup step (useful with overlay add)
echo   --skip-overlay    Skip overlay source resolution and application
echo.
echo Local Tier Options:
echo   --local ^<path^>    After workspace/overlay setup, overwrite each target .github with a
echo                     local overlay tier from PATH (absolute or relative to the current
echo                     directory). PATH is required - local tiers are namespaced per user
echo                     (e.g. an overlay's overlays\local\^<name^>), so bare --local warns and
echo                     skips. Combine with --workspace [--repo] to scope; otherwise applies
echo                     to all workspaces. Skips when the source is missing/empty.
echo.
echo Examples:
echo   # Interactive mode
echo   install.bat
echo.
echo   # Add overlay with all options
echo   install.bat overlay add my-workspace --url ^<ssh-url-of-overlay-repo^> --branch develop --verbose
echo.
echo   # Add overlay with minimal options
echo   install.bat overlay add my-workspace --url ^<ssh-url-of-overlay-repo^>
echo.
echo   # Apply an existing overlay source that is not a Git repository
echo   install.bat overlay add my-workspace --path I:\shared\my-workspace-overlay --workspace my-workspace
echo.
echo   # Update existing overlay
echo   install.bat overlay update my-workspace
echo.
echo   # Update existing overlay for one workspace only
echo   install.bat overlay update my-workspace --workspace my-workspace
echo.
echo   # Remove overlay source directory ^(Git-backed or standalone; confirmation required^)
echo   install.bat overlay remove my-workspace
echo.
echo   # Update or remove an overlay added at a custom path ^(--path is not remembered^)
echo   install.bat overlay update my-workspace --path <FRAMEWORK_HOME>\overlays\my-workspace
echo   install.bat overlay remove my-workspace --path <FRAMEWORK_HOME>\overlays\my-workspace
echo.
echo   # Setup specific workspace only
echo   install.bat --workspace my-workspace
echo.
echo   # Refresh base files while keeping Architecture Bootstrapper documents
echo   install.bat --workspace my-workspace --keep-arch --skip-overlay
echo.
echo   # Setup specific repository path under workspace
echo   install.bat --workspace my-workspace --repo my-repo
echo.
echo   # Setup specific workspace with overlay
echo   install.bat --workspace my-workspace overlay add my-workspace --url ^<ssh-url-of-overlay-repo^>
echo.
echo   # Setup specific repository path under workspace with overlay
echo   install.bat --workspace my-workspace --repo my-repo overlay add my-workspace --url ^<ssh-url-of-overlay-repo^>
echo.
echo   # Apply a custom local folder (absolute path) to one workspace
echo   install.bat --local I:\my\local --workspace my-workspace
echo.
echo   # Apply a custom local folder (relative path) to a specific repository
echo   install.bat --local .\overlays\local --workspace my-workspace --repo my-repo
echo.
exit /b 0

REM ============================================================================
REM Resolve the local overlay tier source for --local into AI_LOCAL_TIER.
REM   --local ^<path^> -> that path (absolute or relative to the caller's cwd).
REM   Bare --local has no default source and is skipped with a warning.
REM ============================================================================
:ResolveLocalTier
set "AI_LOCAL_TIER="
if not "!LOCAL_PATH_IN!"=="" (
    REM Anchor a relative path to the caller's cwd, since pushd changed ours.
    pushd "!INVOKE_CWD!" 2>nul
    for %%I in ("!LOCAL_PATH_IN!") do set "AI_LOCAL_TIER=%%~fI"
    popd 2>nul
    goto :eof
)
REM --local requires an explicit path; there is no default source. Local tiers are
REM namespaced per user (e.g. overlays\local\^<name^>), so bare --local cannot infer one.
echo WARNING: --local was given without a path. There is no default local tier source.
echo   Skipping the local overlay tier. Re-run with --local ^<path^> pointing at a
echo   local subdirectory (e.g. an overlay's overlays\local\^<name^>) to apply one.
goto :eof
