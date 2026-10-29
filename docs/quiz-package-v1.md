# 测验包格式 v1

测验包与学习包独立，用户从“测试”模块导入自己准备的日语单选题。应用不附带题库，也不转换试卷或自动推断正确答案。下面是本项目原创的数据格式说明示例，不是教材题库。

## ZIP 结构

ZIP根目录只含两个UTF-8 JSON：

```text
manifest.json
questions.json
```

只支持普通文件和存储／deflate压缩，不支持加密、链接、分卷、额外目录或其他文件。ZIP最大32 MiB，每个JSON最大8 MiB，展开合计最大16 MiB。校验失败不会切换已有题库。

## manifest.json

```json
{
  "schema_version": "1.0",
  "kind": "quiz",
  "package_id": "original-window-quiz",
  "content_revision": 1,
  "title": "原创读音格式练习",
  "language": "ja",
  "level_tags": ["practice"]
}
```

`package_id` 是最长80字符的小写字母、数字、连字符，首位为字母或数字。`content_revision` 为正整数。相同ID与修订的相同内容重导不会产生副本；内容更新需递增修订并保持题目ID稳定。题库与个人考试记录分开保存。

## questions.json

```json
[
  {
    "id": "window-reading-1",
    "section": "读音练习",
    "prompt": "窓を開けます。",
    "underlines": [{"start": 0, "end": 1}],
    "ruby": [{"start": 2, "end": 3, "reading": "あ"}],
    "choices": [
      {"id": "a", "text": "まど"},
      {"id": "b", "text": "みち"},
      {"id": "c", "text": "いえ"},
      {"id": "d", "text": "はな"}
    ],
    "answer_id": "a",
    "explanation_zh": "「窓」的读音是「まど」。"
  }
]
```

题库包含1至20000题，每题2至8个选项，`answer_id` 必须对应本题选项ID。题目ID和选项ID在各自范围内唯一；ID最长120字符，题干最长10000字符，单个选项最长5000字符。

`underlines` 相对于题干 `prompt`；`ruby` 相对于所属题干或选项 `text`。选项也可有自己的 `ruby` 数组。所有范围使用 UTF-16 码元，起点包含、终点不包含，按起点排序、互不重叠，不得越界或切断代理对。假名与下划线可以相交。`section`、`explanation_zh`、`underlines`、`ruby` 和自备来源 `source` 可省略。

## 会话与记录

用户可设题量、时长、顺序／随机／错题范围及反馈方式。开始后保存题目快照；资料升级不改动已经开始的考试或旧成绩。计时采用本机截止时间，离开页面或切到后台不会暂停计时。导入资料和未交卷试卷不计入已完成成绩。

历史成绩、答题选择、错题统计、未完成试卷和偏好属于个人数据，不应加入公开题库。准备者需自行核对内容准确性与使用授权。
