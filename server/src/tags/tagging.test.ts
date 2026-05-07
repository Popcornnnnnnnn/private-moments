import assert from "node:assert/strict";
import test from "node:test";

import { findReusableTopicTagForName, type TopicTagReuseCandidate } from "./tagging.js";

const candidates: TopicTagReuseCandidate[] = [
  {
    id: "mitm",
    name: "中间人攻击",
    normalizedName: "中间人攻击",
    aliases: [],
  },
  {
    id: "database",
    name: "数据库",
    normalizedName: "数据库",
    aliases: [],
  },
  {
    id: "sales-role",
    name: "销售岗位",
    normalizedName: "销售岗位",
    aliases: [],
  },
  {
    id: "interview",
    name: "面试",
    normalizedName: "面试",
    aliases: [
      {
        alias: "Interview",
        normalizedAlias: "interview",
      },
    ],
  },
];

test("topic reuse matches concrete existing topic inside a more specific suggestion", () => {
  assert.equal(findReusableTopicTagForName("HTTPS 中间人攻击", candidates)?.id, "mitm");
  assert.equal(findReusableTopicTagForName("https中间人攻击", candidates)?.id, "mitm");
});

test("topic reuse ignores punctuation and spacing for compact exact matches", () => {
  assert.equal(findReusableTopicTagForName("SQLite 数据库", candidates)?.id, "database");
});

test("topic reuse uses active aliases as synonyms", () => {
  assert.equal(findReusableTopicTagForName("interview", candidates)?.id, "interview");
});

test("topic reuse does not merge related but non-contained topics", () => {
  assert.equal(findReusableTopicTagForName("销售行业", candidates)?.id, undefined);
});

test("topic reuse avoids broad generic cores", () => {
  const genericCandidates: TopicTagReuseCandidate[] = [
    {
      id: "ai",
      name: "AI",
      normalizedName: "ai",
      aliases: [],
    },
  ];

  assert.equal(findReusableTopicTagForName("AI辅助学习", genericCandidates)?.id, undefined);
});
