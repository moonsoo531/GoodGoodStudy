/// Chinese source UI strings mapped to Japanese and English.
const Map<String, List<String>> quizStrings = {
  "导入选择题测试包": ["選択式テストパッケージを読み込む", "Import a multiple-choice test package"],
  "现在交卷？": ["テストを提出しますか？", "Submit this test?"],
  "继续作答": ["解答を続ける", "Continue answering"],
  "确认交卷": ["提出する", "Submit test"],
  "保存并离开测试？": ["保存してテストを終了しますか？", "Save and leave this test?"],
  "已选答案会保存在本机，可以稍后继续。": [
    "選択した解答はこの端末に保存され、後で再開できます。",
    "Your answers are saved on this device. You can continue later.",
  ],
  "已选答案会保存在本机。计时继续，到期后按已有答案交卷。": [
    "選択した解答はこの端末に保存されます。制限時間は進み続け、時間切れになると解答済みの内容で提出されます。",
    "Your answers are saved on this device. The timer keeps running and submits your saved answers when time expires.",
  ],
  "保存并离开": ["保存して終了", "Save and leave"],
  "测试记录": ["テスト履歴", "Test history"],
  "基础知识测试": ["基礎知識テスト", "Knowledge test"],
  "导入测试包": ["テストパッケージを読み込む", "Import test package"],
  "交卷": ["提出", "Submit"],
  "关闭": ["閉じる", "Close"],
  "显示假名": ["ふりがなを表示", "Show readings"],
  "本资料未提供假名标注": [
    "この教材にはふりがながありません",
    "This material has no reading annotations",
  ],
  "假名": ["ふりがな", "Readings"],
  "选择一本资料，开始测试": ["教材を選んでテストを始めましょう", "Choose material to start a test"],
  "导入准备好的选择题 ZIP 包\n测试记录和错题保存在本机": [
    "選択式テストの ZIP パッケージを読み込みます\nテスト履歴と間違えた問題はこの端末に保存されます",
    "Import a prepared multiple-choice ZIP package\nTest history and mistakes are saved on this device",
  ],
  " · 计时已结束，查看结果": [" · 時間終了、結果を確認", " · Time expired; view results"],
  " · 有未完成测试": [" · 未完了のテストあり", " · Unfinished test"],
  "进入测试  ›": ["テストへ  ›", "Open test  ›"],
  "查看测试记录": ["テスト履歴を見る", "View test history"],
  "继续上次测试": ["前回のテストを再開", "Continue previous test"],
  "出题范围": ["出題範囲", "Question pool"],
  "全部题目": ["すべての問題", "All questions"],
  "错题专项": ["間違えた問題", "Mistakes review"],
  "暂无错题。完成测试后，错题和漏答题会自动收录。": [
    "間違えた問題はまだありません。テストを提出すると、誤答と未解答の問題が自動で追加されます。",
    "No mistakes yet. Incorrect and unanswered questions are added after you finish a test.",
  ],
  "出题顺序": ["出題順", "Question order"],
  "按顺序": ["順番どおり", "In order"],
  "随机": ["ランダム", "Random"],
  "测试题数": ["問題数", "Question count"],
  "测试时间（分钟）": ["制限時間（分）", "Time limit (minutes)"],
  "0 表示不限时": ["0 は時間制限なし", "0 means no time limit"],
  "答案反馈": ["解答の確認", "Answer feedback"],
  "逐题显示答案": ["各問題の解答後に表示", "Show after each answer"],
  "交卷后统一查看": ["提出後にまとめて確認", "Review after submission"],
  "点击选项后显示答案，该题不能再修改。": [
    "選択肢を選ぶと正解が表示され、その問題の解答は変更できなくなります。",
    "The correct answer appears after you choose. You cannot change that answer afterward.",
  ],
  "交卷前可以修改所选答案，结束后统一查看正确答案。": [
    "提出までは解答を変更できます。正解は提出後にまとめて確認します。",
    "You can change answers before submitting and review the correct answers afterward.",
  ],
  "请先完成上次测试": ["前回のテストを先に完了してください", "Finish the previous test first"],
  "开始测试": ["テストを開始", "Start test"],
  "已测进度按完成测试覆盖的题目计算；正确率包含历次交卷中的未答题。错题之后答对，会移出错题范围。": [
    "進捗は提出済みテストで出題された問題数に基づきます。正答率には過去の未解答も含まれます。間違えた問題は、後で正解すると復習対象から外れます。",
    "Progress counts questions covered by completed tests. Accuracy includes unanswered questions from all submissions. Correctly answering a previous mistake removes it from the review pool.",
  ],
  "不限时": ["時間制限なし", "No time limit"],
  "回答正确": ["正解です", "Correct"],
  "未作答": ["未解答", "Unanswered"],
  "回答错误": ["不正解です", "Incorrect"],
  "上一题": ["前の問題", "Previous"],
  "答题卡": ["解答一覧", "Answer sheet"],
  "下一题": ["次の問題", "Next"],
  "答题卡 · 实心表示已选答案": [
    "解答一覧 · 塗りつぶしは解答済み",
    "Answer sheet · Filled items are answered",
  ],
  " · 时间到，自动交卷": [" · 時間切れで自動提出", " · Time expired; submitted automatically"],
  "返回测试设置": ["テスト設定に戻る", "Back to test settings"],
  "你的答案：未作答": ["あなたの解答：未解答", "Your answer: unanswered"],
  "你的答案：": ["あなたの解答：", "Your answer: "],
  "正确答案：": ["正解：", "Correct answer: "],
  "查看全部选项": ["すべての選択肢を見る", "View all choices"],
  "还没有测试记录。": ["テスト履歴はまだありません。", "No test history yet."],
  " · 超时交卷": [" · 時間切れで提出", " · Submitted on timeout"],
  "还有 {count} 道题未作答，交卷后会计入错题。": [
    "未解答が {count} 問あります。提出すると復習対象に含まれます。",
    "{count} questions are unanswered. They will count as mistakes after submission.",
  ],
  "{count} 题": ["{count} 問", "{count} questions"],
  "已测 {count}/{total}": ["出題済み {count}/{total}", "Covered {count}/{total}"],
  "正确率 {value}": ["正答率 {value}", "Accuracy {value}"],
  "错题 {count}": ["間違えた問題 {count}", "Mistakes {count}"],
  "测试 {count} 次": ["テスト {count} 回", "{count} tests"],
  "上次测试 · 已选 {count}/{total} 题": [
    "前回のテスト · 解答済み {count}/{total} 問",
    "Previous test · Answered {count}/{total}",
  ],
  "截止 {time}": ["終了時刻 {time}", "Deadline {time}"],
  "范围内共 {count} 题": ["対象 {count} 問", "{count} questions available"],
  "第 {index}/{total} 题 · 已选 {count} 题": [
    "第 {index}/{total} 問 · 解答済み {count} 問",
    "Question {index}/{total} · Answered {count}",
  ],
  "剩余 {time}": ["残り {time}", "Remaining {time}"],
  "{status} · 正确答案：": ["{status} · 正解：", "{status} · Correct answer: "],
  "已答 {answered} 题 · 未答 {unanswered} 题 · 用时 {time}": [
    "解答済み {answered} 問 · 未解答 {unanswered} 問 · 所要時間 {time}",
    "Answered {answered} · Unanswered {unanswered} · Time {time}",
  ],
  "错题与漏答 {count}": ["誤答・未解答 {count}", "Incorrect and unanswered {count}"],
  "第 {index} 题": ["第 {index} 問", "Question {index}"],
  "{scope} · 用时 {time}": ["{scope} · 所要時間 {time}", "{scope} · Time {time}"],
  "请先继续或交卷当前测试。": [
    "現在のテストを再開するか、先に提出してください。",
    "Continue or submit the current test first.",
  ],
  "测试题数需要在 1–{count} 之间。": [
    "問題数は 1～{count} の範囲で入力してください。",
    "Enter a question count between 1 and {count}.",
  ],
  "测试时间请输入 0–1440 分钟，0 表示不限时。": [
    "制限時間は 0～1440 分で入力してください。0 は時間制限なしです。",
    "Enter a time limit from 0 to 1440 minutes. Use 0 for no time limit.",
  ],
  "当前没有未完成的测试。": ["未完了のテストはありません。", "There is no unfinished test."],
  "时间到，已自动交卷并保存结果。": [
    "時間切れのため自動提出し、結果を保存しました。",
    "Time expired. The test was submitted and the result saved automatically.",
  ],
  "成绩已保存，统计暂时无法刷新：{error}": [
    "結果は保存済みですが、統計を更新できません：{error}",
    "The result is saved, but statistics could not be refreshed: {error}",
  ],
  "只支持 1.0 版日语测验包。": [
    "バージョン 1.0 の日本語テストパッケージのみ対応しています。",
    "Only version 1.0 Japanese test packages are supported.",
  ],
  "测验资料修订号必须为正整数。": [
    "テスト教材の改訂番号は正の整数にしてください。",
    "The test material revision must be a positive integer.",
  ],
  "测验包需要 1 至 20000 道题。": [
    "テストパッケージには 1～20000 問が必要です。",
    "A test package must contain 1 to 20000 questions.",
  ],
  "题目 ID": ["問題 ID", "Question ID"],
  "level_tags 必须为级别字符串数组。": [
    "level_tags はレベル名の文字列配列にしてください。",
    "level_tags must be an array of level strings.",
  ],
  "每题需要 2 至 8 个选项。": [
    "各問題には 2～8 個の選択肢が必要です。",
    "Each question must have 2 to 8 choices.",
  ],
  "选项 ID": ["選択肢 ID", "Choice ID"],
  "正确答案必须引用本题的一个选项 ID。": [
    "正解には、この問題の選択肢 ID を指定してください。",
    "The correct answer must refer to a choice ID in this question.",
  ],
  "题目下划线范围必须为数组。": [
    "問題の下線範囲は配列にしてください。",
    "Question underline ranges must be an array.",
  ],
  "题目下划线范围重叠或切断了字符。": [
    "問題の下線範囲が重なっているか、文字の途中で区切られています。",
    "Question underline ranges overlap or split a character.",
  ],
  "假名范围重叠、切断字符或读音无效。": [
    "ふりがなの範囲が重なるか、文字の途中で区切られるか、読みが無効です。",
    "Reading annotations overlap, split a character, or have an invalid reading.",
  ],
  "每次测试题量为 1 至 2000 题。": [
    "テストごとの問題数は 1～2000 問です。",
    "Each test must contain 1 to 2000 questions.",
  ],
  "测试时长为 0 至 1440 分钟，0 表示不限时。": [
    "制限時間は 0～1440 分です。0 は時間制限なしです。",
    "The test time limit is 0 to 1440 minutes; 0 means no time limit.",
  ],
  "答案显示方式": ["解答の表示方法", "Answer display mode"],
  "测试记录版本无效。": ["テスト記録のバージョンが無効です。", "The test record version is invalid."],
  "测试题目快照无效。": [
    "テスト問題の保存データが無効です。",
    "The saved test question snapshot is invalid.",
  ],
  "测试题目 ID": ["テスト問題 ID", "Test question ID"],
  "测试记录中含有不存在的题目或选项。": [
    "テスト記録に存在しない問題または選択肢が含まれています。",
    "The test record contains a question or choice that does not exist.",
  ],
  "测试记录的当前题目位置无效。": [
    "テスト記録の現在の問題位置が無効です。",
    "The current question position in the test record is invalid.",
  ],
  "测试记录的资料修订号无效。": [
    "テスト記録の教材改訂番号が無効です。",
    "The material revision in the test record is invalid.",
  ],
  "测试记录的起止时间无效。": [
    "テスト記録の開始・終了時刻が無効です。",
    "The start or end time in the test record is invalid.",
  ],
  "测试时间已到，成绩已保存。": [
    "制限時間になりました。結果は保存済みです。",
    "Time has expired. Your result is saved.",
  ],
  "package_id 必须是小写字母、数字或连字符。": [
    "package_id には小文字、数字、ハイフンを使用してください。",
    "package_id must contain lowercase letters, digits, or hyphens.",
  ],
  "测试记录 ID 无效。": ["テスト記録 ID が無効です。", "The test record ID is invalid."],
  "{label} 必须是 JSON 对象。": [
    "{label} は JSON オブジェクトにしてください。",
    "{label} must be a JSON object.",
  ],
  "{key} 必须是非空字符串，且不能过长。": [
    "{key} は空ではない適切な長さの文字列にしてください。",
    "{key} must be a nonempty string within the length limit.",
  ],
  "{key} 必须是整数。": ["{key} は整数にしてください。", "{key} must be an integer."],
  "{key} 必须是数组，且不能过长。": [
    "{key} は適切な長さの配列にしてください。",
    "{key} must be an array within the length limit.",
  ],
  "{label} 重复：{value}": [
    "{label} が重複しています：{value}",
    "Duplicate {label}: {value}",
  ],
  "{label} 无效。": ["{label} が無効です。", "{label} is invalid."],
  "{key} 必须为 ISO 日期时间。": [
    "{key} は ISO 形式の日時にしてください。",
    "{key} must be an ISO date and time.",
  ],
  "请选择已下载到本机的 ZIP 测验包。": [
    "この端末にダウンロード済みの ZIP テストパッケージを選んでください。",
    "Choose a ZIP test package downloaded to this device.",
  ],
  "测验包超过 32 MB，请按资料拆分。": [
    "テストパッケージが 32 MB を超えています。教材ごとに分けてください。",
    "The test package exceeds 32 MB. Split it by material.",
  ],
  "测验包超过 32 MB。": [
    "テストパッケージが 32 MB を超えています。",
    "The test package exceeds 32 MB.",
  ],
  "ZIP 文件损坏或无法识别。": [
    "ZIP ファイルが破損しているか、認識できません。",
    "The ZIP file is damaged or unrecognized.",
  ],
  "测验 ZIP 根目录只能包含 manifest.json 和 questions.json。": [
    "テスト ZIP のルートには manifest.json と questions.json のみを配置してください。",
    "The test ZIP root may only contain manifest.json and questions.json.",
  ],
  "测验包包含重复或大小写冲突的路径。": [
    "テストパッケージに重複したパス、または大文字・小文字が衝突するパスがあります。",
    "The test package contains duplicate or case-conflicting paths.",
  ],
  "测验包含有未定义的文件：{name}": [
    "テストパッケージに未定義のファイルがあります：{name}",
    "The test package contains an undefined file: {name}",
  ],
  "不支持加密、链接、目录或特殊类型的 ZIP 条目。": [
    "暗号化、リンク、ディレクトリ、特殊な ZIP 項目には対応していません。",
    "Encrypted, linked, directory, and special ZIP entries are not supported.",
  ],
  "测验包中的单个 JSON 不能超过 8 MB。": [
    "テストパッケージ内の各 JSON は 8 MB 以下にしてください。",
    "Each JSON file in a test package must not exceed 8 MB.",
  ],
  "测验包解压后超过 16 MB。": [
    "展開後のテストパッケージが 16 MB を超えています。",
    "The unpacked test package exceeds 16 MB.",
  ],
  "测验包缺少清单或题目文件。": [
    "テストパッケージにマニフェストまたは問題ファイルがありません。",
    "The test package is missing its manifest or question file.",
  ],
  "ZIP 文件校验失败：{filename}": [
    "ZIP ファイルの検証に失敗しました：{filename}",
    "ZIP verification failed: {filename}",
  ],
  "不能用旧版测验资料覆盖新版。": [
    "古い改訂のテスト教材で新しい改訂を上書きできません。",
    "An older test material revision cannot replace a newer one.",
  ],
  "同一修订号的测验内容不同，请提高 content_revision。": [
    "同じ改訂番号で内容が異なります。content_revision を増やしてください。",
    "Test content differs under the same revision. Increase content_revision.",
  ],
  "无法导入测验包：{error}": [
    "テストパッケージを読み込めません：{error}",
    "Could not import the test package: {error}",
  ],
  "测验资料 {name} 无法读取，请重新导入相同或更新版本修复。成绩记录会保留。": [
    "テスト教材 {name} を読み込めません。同じ改訂または新しい改訂を再度読み込んで修復してください。結果の記録は保持されます。",
    "Test material {name} could not be read. Reimport the same or a newer revision to repair it. Results are preserved.",
  ],
  "已安装测验包缺少版本记录。": [
    "インストール済みテストパッケージにバージョン記録がありません。",
    "The installed test package has no version record.",
  ],
  "测验包的资料标识或版本记录不一致。": [
    "テストパッケージの教材 ID またはバージョン記録が一致しません。",
    "The test package material ID or version record is inconsistent.",
  ],
  "测验版本记录": ["テストのバージョン記録", "Test version record"],
  "测验包的版本记录无效。": [
    "テストパッケージのバージョン記録が無効です。",
    "The test package version record is invalid.",
  ],
  "questions.json 必须为数组。": [
    "questions.json は配列にしてください。",
    "questions.json must be an array.",
  ],
  "请先导入这本测验资料。": ["先にこのテスト教材を読み込んでください。", "Import this test material first."],
  "未完成测试": ["未完了のテスト", "Unfinished test"],
  "未完成测试的资料标识或状态不一致。": [
    "未完了テストの教材 ID または状態が一致しません。",
    "The unfinished test material ID or status is inconsistent.",
  ],
  "一份成绩归档损坏，原文件已保留；未完成题目仍可继续或重新交卷。": [
    "結果のアーカイブが 1 件破損しています。元のファイルは保持され、未完了の問題は再開または再提出できます。",
    "One result archive is damaged. The original file is preserved; unfinished questions can still be resumed or resubmitted.",
  ],
  "这本资料的未完成测试记录损坏，原文件已保留；已保存成绩不受影响。": [
    "この教材の未完了テスト記録が破損しています。元のファイルは保持され、保存済みの結果には影響しません。",
    "The unfinished test record for this material is damaged. The original is preserved; saved results are unaffected.",
  ],
  "测验设置": ["テスト設定", "Test settings"],
  "这本资料的测验设置损坏，已恢复默认设置；成绩记录会保留。": [
    "この教材のテスト設定が破損しているため、既定の設定に戻しました。結果の記録は保持されます。",
    "Test settings for this material are damaged and have been reset to defaults. Results are preserved.",
  ],
  "测验显示设置": ["テストの表示設定", "Test display settings"],
  "假名显示设置无效。": ["ふりがなの表示設定が無効です。", "The reading display setting is invalid."],
  "这本资料的显示设置损坏，已恢复默认显示；成绩记录会保留。": [
    "この教材の表示設定が破損しているため、既定の表示に戻しました。結果の記録は保持されます。",
    "Display settings for this material are damaged and have been reset to defaults. Results are preserved.",
  ],
  "这本资料已有未完成测试，请继续作答或先交卷。": [
    "この教材には未完了のテストがあります。解答を続けるか、先に提出してください。",
    "This material already has an unfinished test. Continue answering or submit it first.",
  ],
  "目前没有可供测试的错题。": [
    "現在、テストできる間違えた問題はありません。",
    "There are no mistakes available for a review test.",
  ],
  "选项不属于本次测试中的这道题。": [
    "この選択肢は今回のテストの問題に含まれていません。",
    "This choice does not belong to this question in the current test.",
  ],
  "这道题已核对答案，不能再次修改。": [
    "この問題は正解を確認済みのため、解答を変更できません。",
    "This answer has already been checked and cannot be changed.",
  ],
  "这次测试已结束或不存在，请返回资料列表。": [
    "このテストは終了したか、存在しません。教材一覧に戻ってください。",
    "This test has ended or does not exist. Return to the material list.",
  ],
  "测试成绩": ["テスト結果", "Test result"],
  "测试成绩的资料标识或状态无效。": [
    "テスト結果の教材 ID または状態が無効です。",
    "The test result material ID or status is invalid.",
  ],
  "一份测试成绩无法读取，原文件已保留，统计暂不包含该记录。": [
    "テスト結果を 1 件読み込めません。元のファイルは保持され、この記録は統計から一時的に除外されます。",
    "One test result could not be read. The original file is preserved and is temporarily excluded from statistics.",
  ],
  "缺少文件 {name}。": ["ファイル {name} がありません。", "File {name} is missing."],
  "JSON 记录过大。": ["JSON 記録が大きすぎます。", "The JSON record is too large."],
  "{label} 必须为 JSON 对象。": [
    "{label} は JSON オブジェクトにしてください。",
    "{label} must be a JSON object.",
  ],
  "本机测试记录过大，无法保存。": [
    "この端末のテスト記録が大きすぎるため、保存できません。",
    "Local test records are too large to save.",
  ],
};
