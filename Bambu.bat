@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

:: 設定ディレクトリの定義
set "APPDATA_DIR=%APPDATA%\BambuStudio"
set "%LOCALAPPDATA_DIR%=%LOCALAPPDATA%\BambuStudio"
set "PROFILES_DIR=%APPDATA%\BambuStudio_Profiles"
set "BAMBU_EXE=C:\Program Files\Bambu Studio\bambu-studio.exe"

:: プロファイルディレクトリが存在しない場合、環境構築を実施
if not exist "%PROFILES_DIR%" (
    call :CREATE_ENV
    call :END
)

:: 引数が指定された場合、そのプロファイルに切り替え
if not "%~1"=="" (
    if exist "%PROFILES_DIR%\%~1" (
        echo Switching to profile '%~1'...
        set "selected_profile=%~1"
        call :SWITCH_PROFILE
        call :END
    ) else if exist "%~1" (
        echo Received 3D data file: '%~1'
        set "data_file=%~1"
        call :MENU
        call :END
    ) else (
        echo Profile '%~1' does not exist and file '%~1' not found.
        pause
        call :END
    )
)
call :MENU

:ERROR
    echo An error occurred...
    pause
    goto END

:END
    endlocal
    exit

:MENU
    cls
    echo Select a profile:

    :: プロファイルの一覧を表示
    call :GET_CURRENT_PROFILE
    set /a index=0
    for /d %%D in ("%PROFILES_DIR%\*") do (
        set /a index+=1
        set "profile[!index!]=%%~nxD"
        set "target=%%~nxD"
        if /I "!current_profile!"=="!target!" (
            echo !index!. !target!   *
        ) else (
            echo !index!. !target!
        )
    )
    set /a total=!index!

    echo.
    echo N. Create a new profile
    :: echo C. Clean directory
    echo D. Delete profile
    echo E. Exit
    echo no input. Open Bambu Studio with current profile
    echo.

    :: ユーザーの選択を取得
    set "choice="
    set "selected_profile="
    set /p choice="Enter your choice (1-%total%, N, D, E): "

    :: 入力の検証
    if /I "%choice%"=="N" (
        call :CREATE_PROFILE
    ) else if /I "%choice%"=="E" (
        echo Exiting...
        pause
        call :END
    ) else if /I "%choice%"=="D" (
        call :DELETE_PROFILE
    ) else (
        for /L %%i in (1,1,!total!) do (
            if "!choice!"=="%%i" (
                set "selected_profile=!profile[%%i]!"
                call :SWITCH_PROFILE
            )
        )
    )
    
    call :START_BAMBU
    call :END
    exit /b 0

:CREATE_ENV
    echo Start creating environment...
    pause
    echo 1. Creating profile directory.
    set "BACKUP_DIR=%APPDATA%\BambuStudio_Backup"
    if exist "%APPDATA_DIR%" (
        echo Backing up current data to '!BACKUP_DIR!'...
        mkdir "!BACKUP_DIR!"
        xcopy "%APPDATA_DIR%\*" "!BACKUP_DIR!" /E /I /Y >nul
    )
    mkdir "%PROFILES_DIR%"
    echo done.
    echo 2. Creating new profile.
    set /p new_profile=Enter new profile name: 
    if "%new_profile%"=="" (
        choice /C YN /M "Do you want to stop creating environment?"
        if !ERRORLEVEL! NEQ 1 (
            rd /s /q "%PROFILES_DIR%"
            echo Environment creation cancelled.
            pause
            call :END
            exit /b 0
        )
        call :CREATE_ENV
        exit /b 0
    )
    mkdir "%PROFILES_DIR%\%new_profile%"
    echo done.
    echo 3. Copying data from current directory.
    choice /C YN /M "Do you want to copy data from current directory?"
    if !ERRORLEVEL! EQU 1 (
        echo Copying from current directory...
        set "source_dir=%APPDATA_DIR%"
        if not exist "!source_dir!" (
            echo Do not exist BambuStudio data '!source_dir!'.
        ) else (
            echo Detected current BambuStudio data.
            echo Copying data to '%new_profile%'...
            xcopy "!source_dir!\*" "%PROFILES_DIR%\%new_profile%\" /E /I /Y >nul
            echo Data copied.
        )
    ) else (
        echo '!new_profile!' is empty.
        pause
        call :MENU
        exit /b 0
    )

    echo done.
    echo 4. Change profile and open Bambu Studio.
    choice /C YN /M "Do you want to switch to the new profile?"
    if !ERRORLEVEL! NEQ 1 (
        call :MENU
        exit /b 1
    )

    call :EXIT_BAMBU
    call :CREATE_LINK %new_profile%
    
    choice /C YN /M "Do you want to open Bambu Studio with the new profile?"
    if !ERRORLEVEL! NEQ 1 (
        call :MENU
        exit /b 1
    )
    
    call :START_BAMBU
    call :END
    exit /b 0

:SWITCH_PROFILE
    call :GET_CURRENT_PROFILE
    echo Current profle: %current_profile%
    echo Selected profile: %selected_profile%

    :: ターゲットと選択されたプロファイルのパスを比較
    if /I "%current_profile%"=="%selected_profile%" (
        echo The selected profile is already active. No changes made.
        call :START_BAMBU
        call :END
        exit /b 0
    )

    call :EXIT_BAMBU
    call :CREATE_LINK %selected_profile%
    call :START_BAMBU
    call :END
    exit /b 0

:CREATE_PROFILE
    :: 新しいプロファイル名の入力
    set /p new_profile=Enter new profile name: 
    if "%new_profile%"=="" (
        call :MENU
        exit /b 0
    ) else if "%new_profile%"=="*" (
        echo Invalid profile name.
        pause
        call :CREATE_PROFILE
        exit /b 0
    )

    :: 同名のプロファイルが存在するか確認
    if exist "%PROFILES_DIR%\%new_profile%" (
        echo A profile with the same name already exists.
        pause
        call :MENU
        exit /b 0
    )

    :: 新しいプロファイルディレクトリを作成
    choice /C YN /M "Do you want to copy data from other profile or current directory?"
    if !ERRORLEVEL! EQU 1 (
        echo Select a profile:

        set /a index=0
        for /d %%D in ("%PROFILES_DIR%\*") do (
            set /a index+=1
            set "profile[!index!]=%%~nxD"
            echo !index!. %%~nxD
        )
        echo.
        echo C. Copy from current directory
        echo.
        set "total="
        set "choice="
        set /a total=!index!
        set /p choice="Enter your choice (1-!total!, C): "
        
        :: コピーする
        set "source_dir="
        if /I "!choice!"=="" (
            call :MENU
            exit /b 0
        ) else if /I "!choice!"=="C" (
            echo Copying from current directory...
            set "source_dir=%APPDATA_DIR%"
            set "source_profile=<Current Directory>"
        ) else (
            for /L %%i in (1,1,!total!) do (
                if "!choice!"=="%%i" (
                    set "source_profile=!profile[%%i]!"
                    set "source_dir=%PROFILES_DIR%\!source_profile!"
                )
            )
        )

        if not exist "!source_dir!" (
            echo Do not exist the profile '!source_dir!'.
            pause
            call :MENU
            exit /b 0
        )

        echo Selected profile: !source_dir!
        if /I "!source_dir!"=="%PROFILES_DIR%\%new_profile%" (
            echo Error: Source and target directories are the same. Cannot perform a cyclic copy.
            pause
            call :MENU
            exit /b 0
        )
        echo Copying data from '!source_profile!' to '%new_profile%'...
        mkdir "%PROFILES_DIR%\%new_profile%"
        xcopy "!source_dir!\*" "%PROFILES_DIR%\%new_profile%\" /E /I /Y >nul
        echo Data copied.
    ) else (
        mkdir "%PROFILES_DIR%\%new_profile%"
    )
    echo Profile '%new_profile%' was created.

    choice /C YN /M "Do you want to switch to the new profile?"
    if !ERRORLEVEL! NEQ 1 (
        call :MENU
        exit /b 1
    )

    call :EXIT_BAMBU
    call :CREATE_LINK %new_profile%
    
    choice /C YN /M "Do you want to open Bambu Studio with the new profile?"
    if !ERRORLEVEL! NEQ 1 (
        call :MENU
        exit /b 1
    )
    
    call :START_BAMBU
    call :END
    exit /b 0

:DELETE_PROFILE
    set "delete_profile="
    set /p delete_profile=Enter profile name to delete: 

    if "%delete_profile%"=="" (
        call :MENU
        exit /b 0
    ) else if not exist "%PROFILES_DIR%\%delete_profile%" (
        echo Profile '%delete_profile%' does not exist.
        call :DELETE_PROFILE
        exit /b 0
    )

    choice /C YN /M "Are you sure you want to delete profile '!delete_profile!'?"
    if !ERRORLEVEL! NEQ 1 (
        echo Profile deletion cancelled.
        call :MENU
        exit /b 1
    )
    call :GET_CURRENT_PROFILE
    call :GET_BAMBU_ACTIVE
    if /I "%current_profile%"=="%delete_profile%" (
        if /I !bambu_is_active! == 1 (
            echo The selected profile is currently active. It needs to close Bambu Studio before deletion.
            call :EXIT_BAMBU
        )
        call :REMOVE_FOLDER
        call :REMOVE_LOCAL_DIR
    )
    :: プロファイルディレクトリを削除
    echo Deleting profile '!delete_profile!'...
    rmdir /s /q "%PROFILES_DIR%\!delete_profile!"
    echo Profile '%delete_profile%' deleted.
    pause
    cls
    call :MENU
    exit /b 0

:CLEAR_FOLDER
    call :EXIT_BAMBU
    call :REMOVE_FOLDER
    call :REMOVE_LOCAL_DIR
    call :MENU
    exit /b 0

:CREATE_CLEAN_FOLDER
    call :EXIT_BAMBU
    call :REMOVE_FOLDER
    call :REMOVE_LOCAL_DIR

    :: 空のディレクトリを作成
    mkdir "%APPDATA_DIR%"
    echo Created empty directory '%APPDATA_DIR%'.

    call :MENU
    exit /b 0

:CREATE_LINK
    call :REMOVE_FOLDER
    call :REMOVE_LOCAL_DIR
    :: 選択されたプロファイルをシンボリックリンクとして作成
    echo Creating link to profile '%1'...
    mklink /J "%APPDATA_DIR%" "%PROFILES_DIR%\%1" >nul
    exit /b 0

:REMOVE_FOLDER
    :: 現在のシンボリックリンク、ディレクトリを削除
    if exist "%APPDATA_DIR%" (
        rmdir /s /q "%APPDATA_DIR%"
    )
    exit /b 0

:REMOVE_LOCAL_DIR
    if exist "%LOCALAPPDATA_DIR%" (
        rmdir /s /q "%LOCALAPPDATA_DIR%"
    )
    exit /b 0

:START_BAMBU
    echo Launching Bambu Studio...
    :: pause
    start "" "%BAMBU_EXE%" "%data_file%"
    exit /b 0

:EXIT_BAMBU
    :: Bambu Studio が起動している場合、終了する
    call :GET_BAMBU_ACTIVE
    if !bambu_is_active! == 1 (
        echo Bambu Studio is currently running.
        choice /C YN /M "Are you sure you want to close Bambu Studio?"
        if !ERRORLEVEL! NEQ 1 (
            echo Bambu Studio closing cancelled.
            pause
            call :MENU
            exit /b 1
        )
        echo Closing Bambu Studio...
        taskkill /F /IM bambu-studio.exe /T >nul
        timeout /t 3 /nobreak >nul
    )
    exit /b 0

:GET_CURRENT_PROFILE
    set "current_profile="
    :: 現在のシンボリックリンクのターゲットを取得
    for /f "tokens=2 delims=[]" %%F in ('dir "%APPDATA%" ^| findstr /i "<JUNCTION>"') do (
        for %%P in (%%F) do (
            set "current_profile=%%~nxP"
        )
    )
    exit /b 0

:GET_BAMBU_ACTIVE
    set "bambu_is_active="
    tasklist /FI "IMAGENAME eq bambu-studio.exe" | find /I "bambu-studio.exe" >nul
    if !ERRORLEVEL! EQU 0 (
        set "bambu_is_active=1"
    ) else (
        set "bambu_is_active=0"
    )
    exit /b 0