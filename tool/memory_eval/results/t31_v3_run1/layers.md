# t31_v3_run1：抽取 prompt v3 的分层结果

层由服务器按类目和敏感判断决定（`functions/memory.js` `layerFor`），不是模型决定的。敏感的条目要老人在「我記得嘅嘢」确认后才会用。

| 对话 | 陪伴者 | 类目 | 标题：内容 | 敏感 | 层 |
|---|---|---|---|---|---|
| D01 | siu_yan | name | 稱呼：陳太 |  | 共享 |
| D01 | siu_yan | living | 居住情況：自己一個住喺深水埗 |  | 共享 |
| D01 | siu_yan | family | 個女：個女叫阿欣，住沙田 |  | 共享 |
| D01 | siu_yan | family | 個女探訪：阿欣逢禮拜日都會上嚟同陳太食飯 |  | 共享 |
| D01 | siu_yan | 待跟进 | 陳太下個禮拜四要去覆診（2026-10-15） |  | 私有 |
| D02 | tung_tung | preference | 鍾意睇粵劇：鍾意睇粵劇，最鍾意任白（任劍輝、白雪仙）嘅戲 |  | 共享 |
| D02 | tung_tung | health | 腳唔好行唔到山：腳唔好，行唔到山 | 是 | 私有 |
| D02 | tung_tung | family | 阿欣：有個叫阿欣嘅人 |  | 共享 |
| D02 | tung_tung | 待跟进 | 同樓下街坊陳師奶去高山劇場睇大戲（2026-10-09） |  | 私有 |
| D03 | ah_jan_ah_bak | living | 以前住深水埗：以前喺深水埗住咗四十年 |  | 共享 |
| D03 | ah_jan_ah_bak | living | 搬去沙田同阿欣住：上個月搬咗去沙田同阿欣一齊住 |  | 共享 |
| D03 | ah_jan_ah_bak | family | 阿欣：阿欣係佢個女，話佢自己住唔放心 |  | 共享 |
| D03 | ah_jan_ah_bak | name | 陳姑娘：以前北河街檔主叫佢「陳姑娘」 |  | 共享 |
| D03 | ah_jan_ah_bak | story | 北河街買餸：以前喺北河街買餸，個個檔主都識佢 |  | 私有 |
| D03 | ah_jan_ah_bak | health | 年齡：今年八十歲 | 是 | 私有 |
| D04 | ah_jan_ah_bak | name | 稱呼：黃伯 |  | 共享 |
| D04 | ah_jan_ah_bak | family | 老婆：有老婆（已過身） | 是 | 私有 |
| D04 | ah_jan_ah_bak | family | 大仔：大仔叫志強，喺英國 |  | 共享 |
| D04 | ah_jan_ah_bak | family | 細仔：細仔叫志明，住屯門 |  | 共享 |
| D04 | ah_jan_ah_bak | health | 夜晚瞓唔着：夜晚成日瞓唔着 | 是 | 私有 |
| D04 | ah_jan_ah_bak | grief | 掛住老婆：諗起老婆就喊 | 是 | 私有 |
| D04 | ah_jan_ah_bak | 待跟进 | 同志明一齊去拜老婆（2026-11-12） |  | 私有 |
| D05 | siu_yan | routine | 朝早去公園打太極：今朝有去公園打太極 |  | 共享 |
| D05 | siu_yan | routine | 打完太極同老友飲茶：打完太極同啲老友飲咗杯茶 |  | 共享 |
| D05 | siu_yan | feeling | 返屋企覺得冇癮：返到屋企覺得好冇癮 | 是 | 私有 |
| D05 | siu_yan | 待跟进 | 志明帶個孫嚟探黃伯（2026-10-08） |  | 私有 |
| D06 | tung_tung | — | 没有调用模型（forget_request） | — | — |
| D07 | siu_yan | name | 稱呼：李婆婆 |  | 共享 |
| D07 | siu_yan | family | 家務助理：阿芳，菲律賓人，好細心 |  | 共享 |
| D07 | siu_yan | 待跟进 | 李婆婆同阿芳去街市買餸（2026-10-08） |  | 私有 |
| D07 | siu_yan | 待跟进 | 李婆婆八十六歲生日（2026-10-09） |  | 私有 |
| D07 | siu_yan | 待跟进 | 李婆婆去教會探訪活動（2026-10-10） |  | 私有 |
| D08 | ah_jan_ah_bak | story | 出生地及來港時間：細個喺順德出世，十二歲先落嚟香港。 |  | 私有 |
| D08 | ah_jan_ah_bak | story | 製衣廠工作：後生喺製衣廠做車衣，做咗三十年。 |  | 私有 |
| D08 | ah_jan_ah_bak | family | 老公職業：老公以前揸的士，日日夜晚先返屋企。 |  | 共享 |
| D09 | tung_tung | hobby | 鍾意影相：鍾意用手機影相，今朝去公園影紫荊花 |  | 共享 |
| D09 | tung_tung | family | 個孫教用手機影相：個孫教佢用手機影相 |  | 共享 |
| D09 | tung_tung | 待跟进 | 社區中心長者旅行團去大澳（2026-10-31） |  | 私有 |
| D10 | tung_tung | name | 稱呼：張伯，舊同事叫佢阿張 |  | 共享 |
| D10 | tung_tung | living | 居住地區及同住：住將軍澳，同老婆阿玲兩個人住 |  | 共享 |
| D10 | tung_tung | family | 老婆：老婆叫阿玲 |  | 共享 |
| D10 | tung_tung | hobby | 興趣：最鍾意行山 |  | 共享 |
| D10 | tung_tung | 待跟进 | 同幾個舊同事去行麥理浩徑第二段（2026-10-12） |  | 私有 |
| D10 | tung_tung | 待跟进 | 去深圳飲外甥嘅喜酒（2026-10-21） |  | 私有 |
| D11 | siu_yan | health | 驗出糖尿病：上個禮拜驗身驗出有糖尿病，醫生叫佢戒口，唔可以食甜嘢。 | 是 | 私有 |
| D11 | siu_yan | preference | 鍾意食蛋撻：最鍾意食蛋撻。 |  | 共享 |
| D11 | siu_yan | event | 被電話騙案呃兩萬蚊：早排俾人打電話呃咗兩萬蚊，已經報警，但覺得應該追唔返。 | 是 | 私有 |
| D11 | siu_yan | 待跟进 | 下個月五號要再去抽血。（2026-11-05） |  | 私有 |
| D12 | ah_jan_ah_bak | family | 孫女同住：孫女阿瑤同住，讀緊大學 |  | 共享 |
| D12 | ah_jan_ah_bak | family | 老婆名字：老婆叫阿琼，唔係阿玲 |  | 共享 |
| D12 | ah_jan_ah_bak | family | 結婚年數：結婚四十五年 |  | 共享 |
| D12 | ah_jan_ah_bak | preference | 老婆煮餸：老婆煮得一手好菜 |  | 共享 |
| D13 | siu_yan | name | 稱呼：何太 |  | 共享 |
| D13 | siu_yan | living | 居住地區：住黃大仙 |  | 共享 |
| D13 | siu_yan | family | 丈夫狀況：丈夫前年中風，之後要坐輪椅 | 是 | 私有 |
| D13 | siu_yan | routine | 每朝飲早茶：每朝推丈夫落樓下茶樓飲早茶 |  | 共享 |
| D13 | siu_yan | 待跟进 | 帶丈夫去做物理治療（2026-10-14） |  | 私有 |
| D14 | tung_tung | — | 没有调用模型（forget_request） | — | — |
| D15 | ah_jan_ah_bak | story | 後生做點心：後生喺酒樓做點心，做咗二十幾年。 |  | 私有 |
| D15 | ah_jan_ah_bak | family | 個女喺澳洲墨爾本：得一個女，佢喺澳洲墨爾本。 |  | 共享 |
| D15 | ah_jan_ah_bak | routine | 同個女視像：每個禮拜六晚都會同個女視像。 |  | 共享 |
| D16 | ah_jan_ah_bak | name | 稱呼：叫劉國華，大家都叫佢華叔 |  | 共享 |
| D16 | ah_jan_ah_bak | story | 後生做海員：後生一齊做海員，跟船去過日本、新加坡 |  | 私有 |
| D16 | ah_jan_ah_bak | hobby | 捉象棋：好鍾意捉象棋，以前日日喺公園同人捉 |  | 共享 |
| D16 | ah_jan_ah_bak | 待跟进 | 孫俊仔嚟同華叔飲茶（2026-10-11） |  | 私有 |
| D17 | siu_yan | — | 没有事实 | — | — |
| D17 | siu_yan | 待跟进 | 去老人中心剪頭髮（2026-10-08） |  | 私有 |
| D18 | tung_tung | hobby | 以前鍾意捉象棋：以前鍾意捉象棋 |  | 共享 |
| D18 | tung_tung | health | 眼矇睇唔清棋子：眼矇，睇唔清啲棋子，所以冇點捉象棋 | 是 | 私有 |
| D18 | tung_tung | routine | 日日聽收音機講古：改咗日日聽收音機講古 |  | 共享 |
| D18 | tung_tung | 待跟进 | 要去換身份證（2026-11-07） |  | 私有 |
| D19 | tung_tung | name | 稱呼：吳婆婆 |  | 共享 |
| D19 | tung_tung | family | 老公：老公就快九十大壽 |  | 共享 |
| D19 | tung_tung | 待跟进 | 去飲契女嘅喜酒（2026-10-10） |  | 私有 |
| D19 | tung_tung | 待跟进 | 去睇眼科（2026-10-13） |  | 私有 |
| D19 | tung_tung | 待跟进 | 同班姊妹去長洲玩（2026-10-17） |  | 私有 |
| D19 | tung_tung | 待跟进 | 成家人聚會，慶祝老公九十大壽（2026-11-03） |  | 私有 |
| D20 | siu_yan | feeling | 因個仔冇打電話而唔開心同孤獨：個仔成個月冇打過電話嚟，覺得好孤獨，唔係幾開心。 | 是 | 私有 |
| D20 | siu_yan | health | 有高血壓，日日要食藥：有高血壓，日日要食藥，有時都唔記得食。 | 是 | 私有 |
| D20 | siu_yan | 待跟进 | 去街坊會攞免費飯盒（2026-10-10） |  | 私有 |
| D21 | ah_jan_ah_bak | story | 細個喺鴨脷洲長大：細個喺鴨脷洲大 |  | 私有 |
| D21 | ah_jan_ah_bak | family | 阿爸係漁民：阿爸係漁民，成日出海 |  | 共享 |
| D22 | siu_yan | name | 稱呼：鄭伯 |  | 共享 |
| D22 | siu_yan | living | 居住地區：住觀塘嘅公屋 |  | 共享 |
| D22 | siu_yan | routine | 每日散步：日日朝早六點帶狗豆豆去散步 |  | 共享 |
| D22 | siu_yan | family | 寵物：養咗隻狗叫豆豆 |  | 共享 |
| D22 | siu_yan | family | 太太：有太太 |  | 共享 |
| D22 | siu_yan | family | 孫女：有孫女 |  | 共享 |
| D22 | siu_yan | 待跟进 | 同太太去台灣旅行，去日月潭（2026-11-01） |  | 私有 |
| D22 | siu_yan | 待跟进 | 孫女結婚（2026-10-10） |  | 私有 |
| D23 | tung_tung | — | 没有调用模型（forget_request） | — | — |
| D24 | ah_jan_ah_bak | grief | 豆豆離世：鄭伯的狗豆豆上個禮拜走了，十二歲，鄭伯好唔捨得。 | 是 | 私有 |
| D24 | ah_jan_ah_bak | feeling | 屋企好靜：鄭伯覺得屋企冇咗豆豆好靜，朝早都唔知做咩好。 | 是 | 私有 |
| D24 | ah_jan_ah_bak | 待跟进 | 鄭伯同太太帶豆豆嘅骨灰去海邊撒。（2026-10-15） |  | 私有 |
| D25 | tung_tung | name | 稱呼：蘇太 |  | 共享 |
| D25 | tung_tung | living | 居住地區：柴灣 |  | 共享 |
| D25 | tung_tung | hobby | 整嘢食：識整嘢食，整嘅老婆餅好出名，街坊都搶住要 |  | 共享 |
| D26 | siu_yan | routine | 早起習慣：五點幾就醒咗，覺得老人家冇覺瞓 |  | 共享 |
| D26 | siu_yan | family | 個女升職：個女升咗職 |  | 共享 |
| D26 | siu_yan | event | 今晚個女請食飯：今晚個女請去食飯 |  | 私有 |
| D26 | siu_yan | 待跟进 | 去長者中心做義工，教人整餅（2026-10-09） |  | 私有 |
| D26 | siu_yan | 待跟进 | 去覆診（2026-11-10） |  | 私有 |
| D27 | ah_jan_ah_bak | story | 結婚年齡：二十歲結婚 |  | 私有 |
| D27 | ah_jan_ah_bak | family | 老公職業：老公以前做巴士司機，揸咗三十年巴士 |  | 共享 |
| D27 | ah_jan_ah_bak | family | 仔女數目：有三個仔女 |  | 共享 |
| D27 | ah_jan_ah_bak | family | 仔女孝順：兩個仔女好孝順，成日返嚟探我 |  | 共享 |
| D28 | ah_jan_ah_bak | name | 稱呼：馮伯 |  | 共享 |
| D28 | ah_jan_ah_bak | family | 女兒：女兒叫美玲，住喺隔籬座，日日過嚟幫馮伯煮飯 |  | 共享 |
| D28 | ah_jan_ah_bak | story | 開士多：以前喺深水埗開士多，開咗四十年 |  | 私有 |
| D29 | tung_tung | — | 没有调用模型（forget_request） | — | — |
| D30 | siu_yan | family | 美玲請姨姨煮飯：美玲話會請個姨姨嚟幫馮伯煮飯。 |  | 共享 |
| D30 | siu_yan | feeling | 擔心美玲搬遠：對美玲搬去天水圍有少少擔心。 | 是 | 私有 |
| D30 | siu_yan | 待跟进 | 美玲下個禮拜搬去天水圍（2026-10-14） |  | 私有 |
| D30 | siu_yan | 待跟进 | 曾孫出世（2026-12-01） |  | 私有 |

合计事实：共享 58 条，私有 24 条。

| 类目 | 共享 | 私有 |
|---|---|---|
| event | 0 | 2 |
| family | 25 | 2 |
| feeling | 0 | 4 |
| grief | 0 | 2 |
| health | 0 | 6 |
| hobby | 5 | 0 |
| living | 7 | 0 |
| name | 11 | 0 |
| preference | 3 | 0 |
| routine | 7 | 0 |
| story | 0 | 8 |
