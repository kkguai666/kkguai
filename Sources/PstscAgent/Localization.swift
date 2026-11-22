import Foundation

/// The interface language, picked from the Mac's preferred languages (System Settings →
/// General → Language & Region): Chinese, Korean, Japanese or English, falling back to English.
enum UILanguage {
    case chinese, korean, english, japanese

    static let current: UILanguage = {
        for identifier in Locale.preferredLanguages {
            if identifier.hasPrefix("zh") { return .chinese }
            if identifier.hasPrefix("ko") { return .korean }
            if identifier.hasPrefix("ja") { return .japanese }
            if identifier.hasPrefix("en") { return .english }
        }
        return .english
    }()
}

/// Translates a Korean UI string (the source language of the code) into the interface language.
/// Strings with placeholders use String(format:) syntax, e.g. L("연결 끊김: %@", reason).
func L(_ korean: String, _ arguments: CVarArg...) -> String {
    let text: String
    switch UILanguage.current {
    case .korean:
        text = korean
    case .chinese:
        text = Chinese.table[korean] ?? Translations.table[korean]?.en ?? korean
    case .english:
        text = Translations.table[korean]?.en ?? korean
    case .japanese:
        text = Translations.table[korean]?.ja ?? korean
    }
    return arguments.isEmpty ? text : String(format: text, arguments: arguments)
}

private enum Translations {
    static let table: [String: (en: String, ja: String)] = [
        // Connect window
        "kkguai — 원격 PC 연결": ("kkguai — Connect to Remote PC", "kkguai — リモート PC に接続"),
        "원격 PC 주소": ("Remote PC address", "リモート PC のアドレス"),
        "사용자": ("User", "ユーザー"),
        "비밀번호": ("Password", "パスワード"),
        "연결": ("Connect", "接続"),
        "비밀번호를 키체인에 저장하고 다음부터 자동 연결": (
            "Save the password in the Keychain and connect automatically next time",
            "パスワードをキーチェーンに保存し、次回から自動接続"),
        "192.168.0.10 또는 pc.example.com": ("192.168.0.10 or pc.example.com", "192.168.0.10 または pc.example.com"),
        "사용자 이름 또는 MicrosoftAccount\\메일주소": (
            "User name or MicrosoftAccount\\email", "ユーザー名または MicrosoftAccount\\メールアドレス"),
        "주소, 사용자, 비밀번호를 모두 입력하세요.": (
            "Enter the address, user and password.", "アドレス、ユーザー、パスワードをすべて入力してください。"),
        "연결 중…": ("Connecting…", "接続中…"),
        "연결 중… %d%%": ("Connecting… %d%%", "接続中… %d%%"),
        "연결됨": ("Connected", "接続済み"),
        "연결됨, 원격 앱 준비 중…": ("Connected, preparing remote apps…", "接続済み、リモートアプリを準備しています…"),
        "연결 설정을 만들지 못했습니다. 주소 형식을 확인하세요.": (
            "Couldn't set up the connection. Check the address format.",
            "接続を設定できませんでした。アドレスの形式を確認してください。"),
        "비밀번호 또는 계정을 확인하세요.": (
            "Check the password or account.", "パスワードまたはアカウントを確認してください。"),
        "연결 끊김: %@": ("Disconnected: %@", "切断されました: %@"),
        "연결이 끊겼습니다.": ("Disconnected.", "切断されました。"),
        "연결을 끊었습니다.": ("Disconnected.", "切断しました。"),
        "데스크톱 모드로 접속": ("Connect in Desktop Mode", "デスクトップモードで接続"),
        "데스크톱 모드로 연결 중…": ("Connecting in desktop mode…", "デスクトップモードで接続中…"),
        "원격 PC가 이미 사용 중입니다(다른 사용자이거나, PC 앞에서 로그인한 같은 계정). 앱 창 모드로는 연결할 수 없습니다. 데스크톱 모드로 접속하면 그 세션을 넘겨받을 수 있습니다. 넘겨받으면 원격 PC는 잠깁니다.": (
            "The remote PC is already in use (another user, or the same account signed in at the PC). App window mode can't connect. Desktop mode can take over that session; when it does, the remote PC is locked.",
            "リモート PC はすでに使用中です(別のユーザー、または PC の前でサインインした同じアカウント)。アプリウィンドウモードでは接続できません。デスクトップモードで接続すると、そのセッションを引き継げます。引き継ぐと、リモート PC はロックされます。"),

        // Menus
        "Windows 시작": ("Windows Start", "Windows スタート"),
        "시작 메뉴 (어디서나 ⌥Space)": (
            "Start Menu (⌥Space, Anywhere)", "スタートメニュー (どこでも ⌥Space)"),
        "다음 원격 창 (⌥`)": ("Next Remote Window (⌥`)", "次のリモートウィンドウ (⌥`)"),
        "Windows 데스크톱 보기": ("Show Windows Desktop", "Windows デスクトップを表示"),
        "앱 창 모드로 돌아가기": ("Back to App Window Mode", "アプリウィンドウモードに戻る"),
        "경로로 원격 프로그램 실행…": ("Run Remote Program by Path…", "パスを指定してリモートのプログラムを実行…"),
        "Mac 홈 폴더를 원격 PC와 공유 ('Mac' 드라이브)": (
            "Share Mac Home Folder with Remote PC ('Mac' drive)",
            "Mac のホームフォルダーをリモート PC と共有(「Mac」ドライブ)"),
        "실행하면 자동 연결 (키체인에 저장)": (
            "Connect Automatically at Launch (Saved in Keychain)", "起動時に自動接続(キーチェーンに保存)"),
        "로그인 시 kkguai 열기": ("Open kkguai at Login", "ログイン時に kkguai を開く"),
        "Launchpad 앱 폴더 열기": ("Open Launchpad Apps Folder", "Launchpad 用アプリのフォルダーを開く"),
        "원격 PC 리소스 사용량…": ("Remote PC Resource Usage…", "リモート PC のリソース使用量…"),
        "원격 PC 리소스 사용량": ("Remote PC Resource Usage", "リモート PC のリソース使用量"),
        // Updates
        "업데이트 확인 중…": ("Checking for Updates…", "アップデートを確認中…"),
        "최신 버전입니다.": ("You're up to date.", "最新バージョンです。"),
        "현재 버전 %@": ("Current version %@", "現在のバージョン %@"),
        "업데이트를 확인하지 못했습니다.": ("Couldn't check for updates.", "アップデートを確認できませんでした。"),
        "새 버전 %@ 사용 가능": ("Version %@ is available", "新バージョン %@ が利用可能"),
        "다운로드 및 설치": ("Download and Install", "ダウンロードしてインストール"),
        "나중에": ("Later", "後で"),
        "다운로드 중… %d%%": ("Downloading… %d%%", "ダウンロード中… %d%%"),
        "업데이트를 설치하지 못했습니다.": ("Couldn't install the update.", "アップデートをインストールできませんでした。"),
        "%@ 설치를 위해 다시 시작합니다.": ("Restarting to install %@.", "インストールのため再起動します。"),
        "앱이 종료되면 새 버전으로 교체되고 자동으로 다시 열립니다.": ("The app will quit, be replaced, and reopen automatically.", "アプリを終了して新しいバージョンに置き換え、自動で開き直します。"),
        "지금 재시작": ("Restart Now", "今すぐ再起動"),
        "GitHub 응답을 이해하지 못했습니다.": ("Couldn't read GitHub's response.", "GitHub の応答を解釈できませんでした。"),
        "이 릴리스에 macOS 설치 파일이 없습니다.": ("This release has no macOS installer.", "このリリースには macOS 版のインストーラがありません。"),
        "설치 파일을 확인하지 못했습니다.": ("The update file failed its signature check.", "アップデートファイルの署名確認に失敗しました。"),
        // Feedback window
        "피드백 보내기…": ("Send Feedback…", "フィードバックを送る…"),
        "업데이트 확인…": ("Check for Updates…", "アップデートを確認…"),
        "kkguai — 피드백 보내기": ("kkguai — Send Feedback", "kkguai — フィードバック"),
        "불편한 점이나 원하는 기능을 알려 주세요. 모든 메시지를 읽습니다.":
            ("Tell us what is broken or what you want. Every message is read.",
             "不具合や欲しい機能を教えてください。すべて読んでいます。"),
        "답장 받을 이메일 (선택)": ("Your email for a reply (optional)", "返信先メール (任意)"),
        "앱 버전, macOS 버전, 언어만 함께 전송됩니다.":
            ("Only the app version, macOS version and language are sent along.", "アプリのバージョン、macOS のバージョン、言語のみ同送されます。"),
        "보내기": ("Send", "送信"),
        "보내는 중…": ("Sending…", "送信中…"),
        "내용을 입력하세요.": ("Please write a message.", "内容を入力してください。"),
        "감사합니다! 피드백을 보냈습니다.": ("Thank you! Your feedback was sent.", "ありがとうございます。フィードバックを送信しました。"),
        "피드백 수신 주소가 설정되지 않았습니다.": ("No feedback address is configured.", "フィードバックの受信先が設定されていません。"),
        "보내지 못했습니다: %@": ("Could not send: %@", "送信できませんでした: %@"),
        "또는 %@ 로 직접 보내 주세요.": ("Or email %@ directly.", "または %@ へ直接お送りください。"),
        "응답을 받지 못했습니다.": ("No response from the server.", "サーバーから応答がありません。"),
        "연결 끊기": ("Disconnect", "切断"),
        "kkguai 종료": ("Quit kkguai", "kkguai を終了"),
        "편집": ("Edit", "編集"),
        "잘라내기": ("Cut", "カット"),
        "복사": ("Copy", "コピー"),
        "붙여넣기": ("Paste", "ペースト"),
        "전체 선택": ("Select All", "すべてを選択"),
        "창": ("Window", "ウインドウ"),
        "열린 원격 창 없음": ("No Open Remote Windows", "開いているリモートのウィンドウはありません"),
        "(제목 없음)": ("(Untitled)", "(タイトルなし)"),
        " (최소화됨)": (" (Minimized)", "(最小化)"),
        "원격 PC 연결…": ("Connect to Remote PC…", "リモート PC に接続…"),
        "다시 연결하는 중… (취소)": ("Reconnecting… (Cancel)", "再接続中…(キャンセル)"),

        // Dialogs
        "확인": ("OK", "OK"),
        "취소": ("Cancel", "キャンセル"),
        "실행": ("Run", "実行"),
        "원격 PC에서 로그아웃할까요?": ("Sign out of the remote PC?", "リモート PC からサインアウトしますか?"),
        "열려 있는 원격 프로그램이 모두 닫힙니다.": (
            "All open remote programs will close.", "開いているリモートのプログラムはすべて閉じます。"),
        "원격 PC를 다시 시작할까요?": ("Restart the remote PC?", "リモート PC を再起動しますか?"),
        "열려 있는 원격 프로그램이 모두 닫히고 연결이 끊깁니다.": (
            "All open remote programs will close and the connection will end.",
            "開いているリモートのプログラムはすべて閉じ、接続が切れます。"),
        "원격 PC를 끌까요?": ("Shut down the remote PC?", "リモート PC をシャットダウンしますか?"),
        "다시 켜기 전까지 원격 PC에 연결할 수 없습니다.": (
            "You won't be able to connect until it is turned on again.",
            "再び電源を入れるまで、リモート PC に接続できなくなります。"),
        "프로그램을 실행하지 못했습니다": ("Couldn't start the program", "プログラムを起動できませんでした"),
        "%@\n오류 코드: %d\n%@": ("%@\nError code: %d\n%@", "%@\nエラーコード: %d\n%@"),
        "원격 PC가 앱 창 연결을 거부했습니다. 같은 계정이 PC 앞이나 다른 원격 데스크톱에서 로그인돼 있으면 로그아웃한 뒤 다시 연결하거나, 데스크톱 모드로 넘겨받으세요. 처음 쓰는 PC라면 enable-remoteapp.reg 적용 후 재시작하세요.": (
            "The remote PC refused the app-window connection. If the same account is signed in at the PC or from another remote desktop, sign out there and reconnect, or take it over in desktop mode. On a new PC, apply enable-remoteapp.reg and restart.",
            "リモート PC がアプリウィンドウ接続を拒否しました。同じアカウントが PC の前や別のリモートデスクトップでサインインしている場合は、サインアウトしてから再接続するか、デスクトップモードで引き継いでください。初めての PC では enable-remoteapp.reg を適用して再起動してください。"),
        "이 원격 PC는 아직 kkguai 연결 준비가 되어 있지 않습니다. 저장소의 enable-remoteapp.reg를 원격 PC에서 실행하고 재시작한 뒤 다시 연결하세요.": (
            "This remote PC isn't set up for kkguai yet. Run enable-remoteapp.reg from the repository on the remote PC, restart it, then connect again.",
            "このリモート PC はまだ kkguai 接続の準備ができていません。リポジトリの enable-remoteapp.reg をリモート PC で実行し、再起動してから再接続してください。"),
        "원격 PC에서 RemoteApp이 허용되어 있지 않습니다. enable-remoteapp.reg를 적용하세요.": (
            "RemoteApp isn't allowed on the remote PC. Apply enable-remoteapp.reg.",
            "リモート PC で RemoteApp が許可されていません。enable-remoteapp.reg を適用してください。"),
        "원격 PC에서 그 경로의 프로그램을 찾지 못했습니다.": (
            "The program wasn't found at that path on the remote PC.",
            "リモート PC のそのパスにプログラムが見つかりませんでした。"),
        "원격 PC에서 RemoteApp 허용 설정과 프로그램 경로를 확인하세요.": (
            "Check the RemoteApp setting on the remote PC and the program path.",
            "リモート PC の RemoteApp の許可設定とプログラムのパスを確認してください。"),
        "로그인 항목을 바꾸지 못했습니다": ("Couldn't change the login item", "ログイン項目を変更できませんでした"),
        "응용 프로그램 폴더의 kkguai.app으로 실행했을 때만 설정할 수 있습니다.\n%@": (
            "This only works when kkguai runs as kkguai.app from the Applications folder.\n%@",
            "アプリケーションフォルダーの kkguai.app として起動したときだけ設定できます。\n%@"),
        "앱 창 모드로 연결된 상태에서만 측정할 수 있습니다.": (
            "Measuring works only while connected in app window mode.",
            "アプリウィンドウモードで接続しているときだけ測定できます。"),
        "kkguai 연결 세션의 프로세스와 원격 데스크톱 서비스를 3초 동안 측정했습니다.": (
            "Measured the processes of the kkguai session and the Remote Desktop service over 3 seconds.",
            "kkguai の接続セッションのプロセスとリモートデスクトップサービスを 3 秒間測定しました。"),
        "원격 프로그램 실행": ("Run Remote Program", "リモートのプログラムを実行"),
        "원격 PC에 있는 실행 파일의 전체 경로를 입력하세요.": (
            "Enter the full path of the program on the remote PC.",
            "リモート PC にある実行ファイルのフルパスを入力してください。"),

        // Desktop mode
        "Windows 데스크톱": ("Windows Desktop", "Windows デスクトップ"),

        // Start menu
        "앱, 설정 및 문서 검색": ("Search for apps, settings, and documents", "アプリ、設定、ドキュメントの検索"),
        "고정됨": ("Pinned", "ピン留め済み"),
        "모두  ›": ("All  ›", "すべて  ›"),
        "맞춤": ("Recommended", "おすすめ"),
        "‹  뒤로": ("‹  Back", "‹  戻る"),
        "모든 앱": ("All apps", "すべてのアプリ"),
        "검색 결과": ("Search results", "検索結果"),
        "'%@'에 대한 결과가 없습니다": ("No results for '%@'", "「%@」の検索結果はありません"),
        "원격 PC에서 앱 목록을 받아오는 중입니다… %d%%": (
            "Getting the app list from the remote PC… %d%%", "リモート PC からアプリの一覧を取得しています… %d%%"),
        "기존 세션 로그아웃 후 연결": ("Sign Out Session and Connect", "既存セッションをサインアウトして接続"),
        "원격 PC의 기존 세션을 로그아웃할까요?": (
            "Sign out the existing session on the remote PC?", "リモート PC の既存セッションをサインアウトしますか?"),
        "원격 PC의 기존 세션을 화면에 띄웁니다. 저장할 것을 저장한 뒤 시작 → 로그아웃을 누르면 앱 창 모드로 다시 연결합니다. 로그아웃하면 그 세션의 프로그램은 모두 닫힙니다.": (
            "kkguai shows the existing session on the remote PC. Save your work and choose Start → Sign out; kkguai then reconnects in app mode. Signing out closes every program in that session.",
            "リモート PC の既存セッションを表示します。保存してからスタート → サインアウトを選ぶと、アプリウィンドウモードで再接続します。サインアウトするとそのセッションのプログラムはすべて閉じます。"),
        "계속": ("Continue", "続行"),
        "기존 세션을 로그아웃하지 못했습니다. 원격 PC에서 직접 로그아웃한 뒤 다시 연결하세요.": (
            "Couldn't sign out the existing session. Sign out on the remote PC yourself, then connect again.",
            "既存セッションをサインアウトできませんでした。リモート PC で直接サインアウトしてから再接続してください。"),
        "원격 화면에서 저장할 것을 저장한 뒤 시작 → 로그아웃을 누르세요. 로그아웃되면 앱 창 모드로 자동 연결합니다.": (
            "Save your work on the remote screen, then choose Start → Sign out. kkguai reconnects in app mode once you're signed out.",
            "リモート画面で必要なものを保存してから、スタート → サインアウトを選んでください。サインアウトするとアプリウィンドウモードで自動接続します。"),
        "다른 PC로 연결…": ("Connect to Another PC…", "別の PC に接続…"),
        "연결을 누르면 지금 연결이 끊기고 새 PC로 연결합니다.": (
            "Clicking Connect ends the current connection and connects to the new PC.",
            "接続を押すと現在の接続を切断し、新しい PC に接続します。"),
        "원격 PC에 연결하는 중입니다…": (
            "Connecting to the remote PC…", "リモート PC に接続しています…"),
        "앱 아이콘 받는 중… %d%% (%d/%d)": (
            "Getting app icons… %d%% (%d/%d)", "アプリのアイコンを取得中… %d%%(%d/%d)"),
        "고정된 앱이 없습니다. '모두'에서 앱을 우클릭해 고정하세요.": (
            "No pinned apps. Right-click an app in 'All' to pin it.",
            "ピン留めしたアプリはありません。「すべて」でアプリを右クリックしてピン留めしてください。"),
        "최근에 실행한 앱이 여기에 표시됩니다. 고정하려면 앱을 우클릭하세요.": (
            "Recently opened apps appear here. Right-click an app to pin it.",
            "最近使ったアプリがここに表示されます。ピン留めするにはアプリを右クリックしてください。"),
        "시작 화면에 고정": ("Pin to Start", "スタートにピン留めする"),
        "시작 화면에서 고정 해제": ("Unpin from Start", "スタートからピン留めを外す"),
        "전원": ("Power", "電源"),
        "원격 PC 로그아웃…": ("Sign Out of Remote PC…", "リモート PC からサインアウト…"),
        "원격 PC 다시 시작…": ("Restart Remote PC…", "リモート PC を再起動…"),
        "원격 PC 시스템 종료…": ("Shut Down Remote PC…", "リモート PC をシャットダウン…"),

        // Per-program Dock icons
        "Windows 앱": ("Windows App", "Windows アプリ"),

        // Menu bar status and watchdog
        "원격 PC 연결됨 · %d ms": ("Remote PC connected · %d ms", "リモートPC接続済み · %d ms"),
        "원격 PC 확인 중…": ("Checking the remote PC…", "リモートPCを確認中…"),
        "원격 PC에 연결할 수 없습니다": ("Can't reach the remote PC", "リモートPCに接続できません"),
        "시작 메뉴 열기 (⌥Space)": ("Open Start Menu (⌥Space)", "スタートメニューを開く (⌥Space)"),
        "지금 다시 연결": ("Reconnect Now", "今すぐ再接続"),
        "kkguai 열기": ("Open kkguai", "kkguaiを開く"),
        "연결됨 · %d ms": ("Connected · %d ms", "接続済み · %d ms"),
        "원격 PC 도달 가능 · %d ms": ("Remote PC reachable · %d ms", "リモートPC応答あり · %d ms"),
        "연결되지 않음": ("Not connected", "未接続"),
        "대기 중": ("Waiting", "待機中"),
        "화면 채우기": ("Fill the Screen", "画面いっぱいに表示"),
        "항상 위에 두기": ("Keep on Top", "常に最前面"),
        "다음 화면으로 이동": ("Move to Next Screen", "次の画面へ移動"),
        "저장된 PC": ("Saved PCs", "保存したPC"),
        "저장된 PC 없음": ("No saved PCs", "保存したPCはありません"),
        "네트워크에서 찾기": ("Find on Network", "ネットワークで探す"),
        "검색 중…": ("Searching…", "検索中…"),
        "이 네트워크에서": ("On This Network", "このネットワーク上"),
        "3389 포트를 여는 PC를 찾지 못했습니다.": ("No PC with port 3389 responded.", "ポート3389が開いているPCが見つかりませんでした。"),
        "%d대 발견": ("Found %d", "%d台見つかりました"),
        "진단 정보 저장…": ("Save Diagnostics…", "診断情報を保存…"),
        "Mac 클립보드 공유 (텍스트)": ("Share Mac Clipboard (Text)", "Macクリップボードを共有 (テキスト)"),
        "명령": ("Commands", "コマンド"),
        "워크스페이스": ("Workspace", "ワークスペース"),
        "워크스페이스 저장…": ("Save Workspace…", "ワークスペースを保存…"),
        "워크스페이스 저장": ("Save Workspace", "ワークスペースを保存"),
        "지금 실행 중인 앱 %d개를 이 이름으로 저장합니다.": (
            "Saves the %d apps that are running now under this name.",
            "現在実行中のアプリ%d個をこの名前で保存します。"),
        "지금 실행 중인 앱이 없습니다.": ("No apps are running now.", "実行中のアプリがありません。"),
        "저장된 워크스페이스 없음": ("No saved workspaces", "保存されたワークスペースはありません"),
        "연결된 후에 열 수 있습니다.": ("Open it once connected.", "接続してから開けます。"),
        "워크스페이스: %@": ("Workspace: %@", "ワークスペース: %@"),
        "이름": ("Name", "名前"),
        "저장": ("Save", "保存"),
        "진단 정보를 저장했습니다.": ("Diagnostics saved.", "診断情報を保存しました。"),
        "진단 정보를 저장하지 못했습니다.": ("Could not save diagnostics.", "診断情報を保存できませんでした。"),
        "진단 정보 첨부 (버전, 연결 상태, 최근 로그)": (
            "Attach diagnostics (version, connection state, recent log)",
            "診断情報を添付 (バージョン、接続状態、最近のログ)"),
    ]
}

/// Simplified Chinese translations, keyed by the same Korean source strings.
private enum Chinese {
    static let table: [String: String] = [
        "kkguai — 원격 PC 연결": "kkguai — 连接到远程电脑",
        "시작 메뉴 (어디서나 ⌥Space)": "开始菜单（任意位置 ⌥Space）",
        "다음 원격 창 (⌥`)": "下一个远程窗口（⌥`）",
        "원격 PC 주소": "远程电脑地址",
        "사용자": "用户名",
        "비밀번호": "密码",
        "연결": "连接",
        "비밀번호를 키체인에 저장하고 다음부터 자동 연결": "把密码保存到钥匙串，下次自动连接",
        "192.168.0.10 또는 pc.example.com": "192.168.0.10 或 pc.example.com",
        "사용자 이름 또는 MicrosoftAccount\\메일주소": "用户名或 MicrosoftAccount\\邮箱",
        "주소, 사용자, 비밀번호를 모두 입력하세요.": "请填写地址、用户名和密码。",
        "연결 중…": "连接中…",
        "연결 중… %d%%": "连接中… %d%%",
        "연결됨": "已连接",
        "연결됨, 원격 앱 준비 중…": "已连接，正在准备远程应用…",
        "연결 설정을 만들지 못했습니다. 주소 형식을 확인하세요.": "无法建立连接，请检查地址格式。",
        "비밀번호 또는 계정을 확인하세요.": "请检查密码或账户。",
        "연결 끊김: %@": "连接已断开：%@",
        "연결이 끊겼습니다.": "连接已断开。",
        "연결을 끊었습니다.": "连接已断开。",
        "데스크톱 모드로 접속": "以桌面模式连接",
        "데스크톱 모드로 연결 중…": "正在以桌面模式连接…",
        "원격 PC가 이미 사용 중입니다(다른 사용자이거나, PC 앞에서 로그인한 같은 계정). 앱 창 모드로는 연결할 수 없습니다. 데스크톱 모드로 접속하면 그 세션을 넘겨받을 수 있습니다. 넘겨받으면 원격 PC는 잠깁니다.": "远程电脑正在被使用（其他用户，或同一账户已在电脑前登录）。应用窗口模式无法连接。以桌面模式连接可以接管该会话；接管后远程电脑会锁定。",
        "Windows 시작": "Windows 开始菜单",
        "Windows 데스크톱 보기": "显示 Windows 桌面",
        "앱 창 모드로 돌아가기": "返回应用窗口模式",
        "경로로 원격 프로그램 실행…": "按路径运行远程程序…",
        "Mac 홈 폴더를 원격 PC와 공유 ('Mac' 드라이브)": "与远程电脑共享 Mac 个人文件夹（「Mac」驱动器）",
        "실행하면 자동 연결 (키체인에 저장)": "启动时自动连接（保存在钥匙串）",
        "로그인 시 kkguai 열기": "登录时打开 kkguai",
        "Launchpad 앱 폴더 열기": "打开 Launchpad 应用文件夹",
        "원격 PC 리소스 사용량…": "远程电脑资源占用…",
        "원격 PC 리소스 사용량": "远程电脑资源占用",
        "업데이트 확인 중…": "正在检查更新…",
        "최신 버전입니다.": "已是最新版本。",
        "현재 버전 %@": "当前版本 %@",
        "업데이트를 확인하지 못했습니다.": "无法检查更新。",
        "새 버전 %@ 사용 가능": "发现新版本 %@",
        "다운로드 및 설치": "下载并安装",
        "나중에": "稍后",
        "다운로드 중… %d%%": "正在下载… %d%%",
        "업데이트를 설치하지 못했습니다.": "无法安装更新。",
        "%@ 설치를 위해 다시 시작합니다.": "正在重启以安装 %@。",
        "앱이 종료되면 새 버전으로 교체되고 자동으로 다시 열립니다.": "App 会退出、被替换，然后自动重新打开。",
        "지금 재시작": "立即重启",
        "GitHub 응답을 이해하지 못했습니다.": "无法读取 GitHub 的响应。",
        "이 릴리스에 macOS 설치 파일이 없습니다.": "这个版本没有 macOS 安装包。",
        "설치 파일을 확인하지 못했습니다.": "更新文件的签名校验没有通过。",
        "피드백 보내기…": "发送反馈…",
        "업데이트 확인…": "检查更新…",
        "kkguai — 피드백 보내기": "kkguai — 发送反馈",
        "불편한 점이나 원하는 기능을 알려 주세요. 모든 메시지를 읽습니다.": "告诉我们哪里不好用，或你希望有什么功能。每条消息都会看。",
        "답장 받을 이메일 (선택)": "接收回复的邮箱（选填）",
        "앱 버전, macOS 버전, 언어만 함께 전송됩니다.": "只会附带 App 版本、macOS 版本和界面语言。",
        "보내기": "发送",
        "보내는 중…": "发送中…",
        "내용을 입력하세요.": "请先写点内容。",
        "감사합니다! 피드백을 보냈습니다.": "谢谢！反馈已发送。",
        "피드백 수신 주소가 설정되지 않았습니다.": "没有配置反馈接收地址。",
        "보내지 못했습니다: %@": "发送失败：%@",
        "또는 %@ 로 직접 보내 주세요.": "或直接发邮件到 %@。",
        "응답을 받지 못했습니다.": "服务器没有响应。",
        "연결 끊기": "断开连接",
        "kkguai 종료": "退出 kkguai",
        "편집": "编辑",
        "잘라내기": "剪切",
        "복사": "拷贝",
        "붙여넣기": "粘贴",
        "전체 선택": "全选",
        "창": "窗口",
        "열린 원격 창 없음": "没有打开的远程窗口",
        "(제목 없음)": "（未命名）",
        " (최소화됨)": "（已最小化）",
        "원격 PC 연결…": "连接到远程电脑…",
        "다시 연결하는 중… (취소)": "正在重新连接…（取消）",
        "확인": "好",
        "취소": "取消",
        "실행": "运行",
        "원격 PC에서 로그아웃할까요?": "要注销远程电脑吗？",
        "열려 있는 원격 프로그램이 모두 닫힙니다.": "所有打开的远程程序都会关闭。",
        "원격 PC를 다시 시작할까요?": "要重启远程电脑吗？",
        "열려 있는 원격 프로그램이 모두 닫히고 연결이 끊깁니다.": "所有打开的远程程序都会关闭，连接也会断开。",
        "원격 PC를 끌까요?": "要关闭远程电脑吗？",
        "다시 켜기 전까지 원격 PC에 연결할 수 없습니다.": "在重新开机之前无法连接。",
        "프로그램을 실행하지 못했습니다": "无法启动程序",
        "%@\n오류 코드: %d\n%@": "%@\n错误代码：%d\n%@",
        "원격 PC가 앱 창 연결을 거부했습니다. 같은 계정이 PC 앞이나 다른 원격 데스크톱에서 로그인돼 있으면 로그아웃한 뒤 다시 연결하거나, 데스크톱 모드로 넘겨받으세요. 처음 쓰는 PC라면 enable-remoteapp.reg 적용 후 재시작하세요.": "远程电脑拒绝了应用窗口连接。如果同一账户已在电脑前或另一个远程桌面登录，请先在那里注销再连接，或用桌面模式接管。如果是在一台新电脑上使用，请先应用 enable-remoteapp.reg 并重启。",
        "이 원격 PC는 아직 kkguai 연결 준비가 되어 있지 않습니다. 저장소의 enable-remoteapp.reg를 원격 PC에서 실행하고 재시작한 뒤 다시 연결하세요.": "这台远程电脑还没有为 kkguai 做好准备。请在远程电脑上运行仓库里的 enable-remoteapp.reg，重启后再连接。",
        "원격 PC에서 RemoteApp이 허용되어 있지 않습니다. enable-remoteapp.reg를 적용하세요.": "远程电脑没有允许 RemoteApp。请应用 enable-remoteapp.reg。",
        "원격 PC에서 그 경로의 프로그램을 찾지 못했습니다.": "在远程电脑上的该路径没有找到程序。",
        "원격 PC에서 RemoteApp 허용 설정과 프로그램 경로를 확인하세요.": "请检查远程电脑的 RemoteApp 设置和程序路径。",
        "로그인 항목을 바꾸지 못했습니다": "无法修改登录项",
        "응용 프로그램 폴더의 kkguai.app으로 실행했을 때만 설정할 수 있습니다.\n%@": "只有在「应用程序」文件夹里以 kkguai.app 运行时才能设置。\n%@",
        "앱 창 모드로 연결된 상태에서만 측정할 수 있습니다.": "只有在应用窗口模式下连接时才能测量。",
        "kkguai 연결 세션의 프로세스와 원격 데스크톱 서비스를 3초 동안 측정했습니다.": "已对 kkguai 连接会话的进程和远程桌面服务测量了 3 秒。",
        "원격 프로그램 실행": "运行远程程序",
        "원격 PC에 있는 실행 파일의 전체 경로를 입력하세요.": "请输入远程电脑上程序可执行文件的完整路径。",
        "Windows 데스크톱": "Windows 桌面",
        "앱, 설정 및 문서 검색": "搜索应用、设置和文档",
        "고정됨": "已固定",
        "모두  ›": "全部  ›",
        "맞춤": "推荐",
        "‹  뒤로": "‹  返回",
        "모든 앱": "所有应用",
        "검색 결과": "搜索结果",
        "'%@'에 대한 결과가 없습니다": "没有找到「%@」的结果",
        "원격 PC에서 앱 목록을 받아오는 중입니다… %d%%": "正在从远程电脑获取应用列表… %d%%",
        "기존 세션 로그아웃 후 연결": "注销现有会话后连接",
        "원격 PC의 기존 세션을 로그아웃할까요?": "要注销远程电脑上的现有会话吗？",
        "원격 PC의 기존 세션을 화면에 띄웁니다. 저장할 것을 저장한 뒤 시작 → 로그아웃을 누르면 앱 창 모드로 다시 연결합니다. 로그아웃하면 그 세션의 프로그램은 모두 닫힙니다.": "kkguai 会把远程电脑上的现有会话显示出来。保存好工作后选择「开始 → 注销」，kkguai 会重新以应用窗口模式连接。注销会关闭该会话里的所有程序。",
        "계속": "继续",
        "기존 세션을 로그아웃하지 못했습니다. 원격 PC에서 직접 로그아웃한 뒤 다시 연결하세요.": "无法注销现有会话。请在远程电脑上手动注销后再连接。",
        "원격 화면에서 저장할 것을 저장한 뒤 시작 → 로그아웃을 누르세요. 로그아웃되면 앱 창 모드로 자동 연결합니다.": "在远程画面上保存好工作，然后选择「开始 → 注销」。注销后 kkguai 会自动以应用窗口模式重连。",
        "다른 PC로 연결…": "连接另一台电脑…",
        "연결을 누르면 지금 연결이 끊기고 새 PC로 연결합니다.": "点击「连接」会断开当前连接，并连接到新的电脑。",
        "원격 PC에 연결하는 중입니다…": "正在连接远程电脑…",
        "앱 아이콘 받는 중… %d%% (%d/%d)": "正在获取应用图标… %d%%（%d/%d）",
        "고정된 앱이 없습니다. '모두'에서 앱을 우클릭해 고정하세요.": "还没有固定的应用。在「全部」里右键点击应用即可固定。",
        "최근에 실행한 앱이 여기에 표시됩니다. 고정하려면 앱을 우클릭하세요.": "最近打开的应用会显示在这里。右键点击应用可以固定。",
        "시작 화면에 고정": "固定到「开始」",
        "시작 화면에서 고정 해제": "从「开始」取消固定",
        "전원": "电源",
        "원격 PC 로그아웃…": "注销远程电脑…",
        "원격 PC 다시 시작…": "重启远程电脑…",
        "원격 PC 시스템 종료…": "关闭远程电脑…",
        "Windows 앱": "Windows 应用",
        "원격 PC 연결됨 · %d ms": "已连接远程电脑 · %d ms",
        "원격 PC 확인 중…": "正在检查远程电脑…",
        "원격 PC에 연결할 수 없습니다": "无法连接远程电脑",
        "시작 메뉴 열기 (⌥Space)": "打开开始菜单（⌥Space）",
        "지금 다시 연결": "立即重新连接",
        "kkguai 열기": "打开 kkguai",
        "연결됨 · %d ms": "已连接 · %d ms",
        "원격 PC 도달 가능 · %d ms": "远程电脑可达 · %d ms",
        "연결되지 않음": "未连接",
        "대기 중": "等待中",
        "화면 채우기": "填满屏幕",
        "항상 위에 두기": "保持在最前面",
        "다음 화면으로 이동": "移到下一个屏幕",
        "저장된 PC": "已保存的电脑",
        "저장된 PC 없음": "没有已保存的电脑",
        "네트워크에서 찾기": "在网络中查找",
        "검색 중…": "搜索中…",
        "이 네트워크에서": "在此网络中",
        "3389 포트를 여는 PC를 찾지 못했습니다.": "没有找到开放 3389 端口的电脑。",
        "%d대 발견": "找到 %d 台",
        "진단 정보 저장…": "保存诊断信息…",
        "Mac 클립보드 공유 (텍스트)": "共享 Mac 剪贴板（文本）",
        "명령": "命令",
        "워크스페이스": "工作区",
        "워크스페이스 저장…": "保存工作区…",
        "워크스페이스 저장": "保存工作区",
        "지금 실행 중인 앱 %d개를 이 이름으로 저장합니다.": "把当前运行的 %d 个应用保存为这个名称。",
        "지금 실행 중인 앱이 없습니다.": "现在没有正在运行的应用。",
        "저장된 워크스페이스 없음": "没有已保存的工作区",
        "연결된 후에 열 수 있습니다.": "连接后才能打开。",
        "워크스페이스: %@": "工作区：%@",
        "이름": "名称",
        "저장": "保存",
        "진단 정보를 저장했습니다.": "诊断信息已保存。",
        "진단 정보를 저장하지 못했습니다.": "无法保存诊断信息。",
        "진단 정보 첨부 (버전, 연결 상태, 최근 로그)": "附上诊断信息（版本、连接状态、最近的日志）",
    ]
}
