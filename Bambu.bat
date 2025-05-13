@echo off
chcp 65001 >nul
:: 管理者権限で実行されているか確認
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo 管理者権限で再実行します...
    if "%~1"=="" (
        powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    ) else (
        powershell -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    )
    exit /b
)
setlocal EnableDelayedExpansion

:: 設定ディレクトリの定義
set "APPDATA_DIR=%APPDATA%\BambuStudio"
set "PROFILES_DIR=%APPDATA%\BambuStudio_Profiles"
set "BAMBU_EXE=C:\Program Files\Bambu Studio\bambu-studio.exe"

:: プロファイルディレクトリが存在しない場合、作成
if not exist "%PROFILES_DIR%" (
    mkdir "%PROFILES_DIR%"
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
    @REM cls
    echo Select a profile:

    :: プロファイルの一覧を表示
    set /a index=0
    for /d %%D in ("%PROFILES_DIR%\*") do (
        set /a index+=1
        set "profile[!index!]=%%~nxD"
        echo !index!. %%~nxD
    )
    set /a total=!index!

    echo.
    echo N. Create a new profile
    :: echo C. Clean directory
    echo D. Delete profile
    echo E. Exit
    echo.

    :: ユーザーの選択を取得
    set "choice="
    set "selected_profile="
    set /p choice=Enter your choice (1-%total%, N, D, E):

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

    echo Invalid selection.
    call :MENU
    exit /b 0

:SWITCH_PROFILE
    :: 現在のシンボリックリンクのターゲットを取得
    for /f "tokens=2 delims=[]" %%A in ('dir "%APPDATA%" ^| findstr /i "<SYMLINKD>"') do (
        set "current_target=%%A"
    )

    echo Current target: !current_target!
    echo Selected profile: %selected_profile%

    :: ターゲットと選択されたプロファイルのパスを比較
    if /I "!current_target!"=="%PROFILES_DIR%\%selected_profile%" (
        echo The selected profile is already active. No changes made.
        call :START_BAMBU
        call :END
        exit /b 0
    )

    call :EXIT_BAMBU
    call :CREATE_FOLDER %selected_profile%
    call :START_BAMBU
    call :END
    exit /b 0

:CREATE_PROFILE
    :: 新しいプロファイル名の入力
    set /p new_profile=Enter new profile name: 

    :: 同名のプロファイルが存在するか確認
    if exist "%PROFILES_DIR%\%new_profile%" (
        echo A profile with the same name already exists.
        pause
        call :MENU
    )

    :: 新しいプロファイルディレクトリを作成
    mkdir "%PROFILES_DIR%\%new_profile%"
    
    call :EXIT_BAMBU
    call :CREATE_FOLDER %new_profile%
    call :START_BAMBU
    call :END
    exit /b 0

:DELETE_PROFILE
    set "delete_profile="
    set /p delete_profile=Enter profile name to delete: 

    :: 同名のプロファイルが存在するか確認
    if "%delete_profile%"=="" (
        call :MENU
        exit /b 0
    ) else if exist "%PROFILES_DIR%\%delete_profile%" (
        choice /C YN /M "Are you sure you want to delete profile '!delete_profile!'?"
        if !ERRORLEVEL! NEQ 1 (
            echo Profile deletion cancelled.
            call :MENU
            exit /b 1
        )
        echo Deleting profile '!delete_profile!'...
        :: プロファイルディレクトリを削除
        rmdir /s /q "%PROFILES_DIR%\!delete_profile!"
        echo Profile '%delete_profile%' deleted.
        pause
        cls
        call :MENU
    ) else (
        echo Profile '%delete_profile%' does not exist.
        call :DELETE_PROFILE
    )
    exit /b 0

:CLEAR_FOLDER
    call :EXIT_BAMBU
    call :REMOVE_FOLDER
    call :MENU
    exit /b 0

:CLEATE_CLEAN_FOLDER
    call :EXIT_BAMBU
    call :REMOVE_FOLDER

    :: 空のディレクトリを作成
    mkdir "%APPDATA_DIR%"
    echo Created empty directory '%APPDATA_DIR%'.

    call :MENU
    exit /b 0

:CREATE_FOLDER
    call :REMOVE_FOLDER
    :: 選択されたプロファイルをシンボリックリンクとして作成
    echo Creating symbolic link to profile '%1'...
    mklink /D "%APPDATA_DIR%" "%PROFILES_DIR%\%1" >nul
    exit /b 0

:REMOVE_FOLDER
    :: 現在のシンボリックリンク、ディレクトリを削除
    if exist "%APPDATA_DIR%" (
        fsutil reparsepoint query "%APPDATA_DIR%" >nul 2>&1
        if !ERRORLEVEL!==0 (
            echo Removing existing symbolic link...
            rmdir "%APPDATA_DIR%"
        ) else (
            echo Removing existing directory...
            rd /s /q "%APPDATA_DIR%"
        )
    )
    exit /b 0

:START_BAMBU
    echo Launching Bambu Studio...
    :: pause
    start "" "%BAMBU_EXE%" "%data_file%"
    exit /b 0

:EXIT_BAMBU
    :: Bambu Studio が起動している場合、終了する
    tasklist /FI "IMAGENAME eq bambu-studio.exe" | find /I "bambu-studio.exe" >nul
    if !ERRORLEVEL! == 0 (
        echo Bambu Studio is currently running.
        choice /C YN /M "Are you sure you want to switch profiles?"
        if !ERRORLEVEL! NEQ 1 (
            echo Profile switch cancelled.
            call :MENU
            exit /b 1
        )
        echo Closing Bambu Studio...
        taskkill /F /IM bambu-studio.exe /T >nul
        timeout /t 3 /nobreak >nul
    )
    exit /b 0