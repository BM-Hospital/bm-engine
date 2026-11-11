import { cmp, summary } from "./cmp1.mjs";
const texts = [
 "Hello, world! This is a test of the emergency broadcast system (really). Is it? Yes: it is; 3.14159 and 1,000,000 or $5.00 at 50% off.",
 "Visit https://example.com/path/to/page?query=1&b=2#frag or mail someone@example.com now",
 "Một hai ba bốn năm sáu bảy tám chín mười. Tiếng Việt có dấu: ắ ằ ẳ ẵ ặ ấ ầ ẩ ẫ ậ ế ề ể ễ ệ ố ồ ổ ỗ ộ ớ ờ ở ỡ ợ ứ ừ ử ữ ự Ư Ơ Đ đ",
 "AVAVAV ToToTo WAWAWA Ty Yo LT P. F, r. y, 11 17 71 \"quoted\" 'single' “curly” ‘x’ T-shirt e-mail co-op x-ray 10-20 -5 a-1",
 "Supercalifragilisticexpialidocious pneumonoultramicroscopicsilicovolcanoconiosis antidisestablishmentarianism",
 "a -> b => c <- d 1:2 12:30 3x4 A/B and/or [x] {y} <z> a*b a+b a=b a_b a|b a~b a^b #tag @user 100% R&D c++ ;-) :-( ... wait…what—yes–no",
 "office affluent fjord file flight ffi ffl fi fl ff waffle",
 "  leading and   multiple    spaces   and trailing  ",
 "line one\nline two\n\nline four\twith tab",
 "nbsp joined words and soft­hyphen­ated zero​width​space",
];
const fams = ["Inter", "Noto Sans", "Roboto"];
for (const fam of fams) for (const tx of texts) for (const w of [80, 150, 260, 420]) {
  await cmp(tx, { fontFamily: fam, fontSize: 18 }, w);
}
summary();
