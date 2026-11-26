# Hướng dẫn ứng dụng Poki cho iPhone

[English](iphone-guide.md) | [简体中文](iphone-guide.zh-CN.md) | [繁體中文](iphone-guide.zh-TW.md) | [日本語](iphone-guide.ja.md) | [한국어](iphone-guide.ko.md) | [Español](iphone-guide.es.md) | Tiếng Việt

Hướng dẫn này bao gồm toàn bộ yêu cầu hệ thống, chi tiết cài đặt, cách cập nhật, câu hỏi thường gặp, các giới hạn đã biết và ví dụ tác vụ cho ứng dụng Poki trên iPhone.

Xem nội dung thay đổi trong từng phiên bản tại [CHANGELOG.md](../CHANGELOG.md).

## Những gì bạn cần

| | Yêu cầu |
| --- | --- |
| iPhone | iOS 18 trở lên, tức iPhone XS, XR, SE (thế hệ 2) hoặc mới hơn. Poki đã được kiểm thử trên iPhone thật chạy iOS 27. |
| Máy tính | Một máy Mac với macOS 14 trở lên, hoặc Windows PC (x64) đã cài Apple Devices hoặc iTunes. Cài đặt bằng agent trên máy Mac còn cần Node.js 24 trở lên. |
| Cáp và tài khoản | Một cáp dữ liệu USB và một tài khoản Apple. Với tài khoản miễn phí, chữ ký chỉ kéo dài 7 ngày, và Poki Setup có thể gia hạn giúp bạn. |
| Kết nối | Một ứng dụng VPN trên iPhone định tuyến `10.7.0.1` quay lại iPhone. LocalDevVPN miễn phí trên App Store dùng được, Karing và Shadowrocket cũng vậy khi thiết lập theo hướng dẫn của Poki. |
| Tài khoản mô hình | Tài khoản của chính bạn. Đăng nhập bằng gói ChatGPT Plus hoặc Pro là cách bắt đầu dễ nhất. Bạn cũng có thể dán API key từ Anthropic, OpenAI, Gemini, DeepSeek, OpenRouter, hoặc OpenCode Go, hoặc dùng máy chủ tương thích OpenAI của riêng bạn. Gói đăng ký Claude không thể dùng để đăng nhập, vì vậy hãy dùng Anthropic API key thay thế. |

Trên iOS 27 trở lên, Poki điều khiển iPhone thông qua các dịch vụ gốc của hệ thống. Trên iOS 18 đến 26, Poki dùng một phiên XCTest thay thế, phiên này cần bật UI Automation trong phần cài đặt Developer của iPhone. Ứng dụng cũng cài đặt được trên iPad với iPadOS 18 trở lên.

Ứng dụng iPhone sử dụng tài khoản mô hình của chính bạn. Gói đăng ký coding agent của bạn không tự động kết nối tài khoản đó với Poki. Nếu bạn chỉ muốn dùng Poki MCP trong coding agent hiện có, hãy làm theo [hướng dẫn cài đặt MCP](install.md) thay thế; MCP sử dụng quyền truy cập mô hình của client đó.

## Chi tiết cài đặt

### Cài đặt một chạm (khuyên dùng)

Bạn chỉ cần kết nối và mở khóa iPhone, đăng nhập khi được yêu cầu, và hoàn thành các bước về quyền trên iPhone, kết nối cục bộ và tài khoản mô hình.

Hãy nói với agent của bạn, chẳng hạn Claude Code hoặc Codex:

```text
Cài đặt Poki lên iPhone của tôi từ https://github.com/JosssphZhou/poki
```

Agent sẽ làm theo [kỹ năng install-poki](../skills/install-poki/SKILL.md) và chạy `bin/install-iphone.mjs`, script này tự thực hiện mọi bước có thể. Bạn chỉ làm những gì iOS yêu cầu: nhập tài khoản Apple vào cửa sổ Poki Setup trên máy Mac, chạm Tin cậy (Trust) và bật Developer Mode trên iPhone, tin cậy nhà phát triển, rồi mở Poki. Khi Poki mở lần đầu, ứng dụng sẽ hỏi về Automation Mode: chạm Continue và nhập mật mã iPhone. Nếu bạn hủy, hãy bật lại Poki để được hỏi lại. Agent sẽ nói cho bạn từng bước bằng một câu khi bước đó xuất hiện. Tài khoản Apple miễn phí là đủ.

Trình cài đặt hiện tại chọn kênh Beta. Các tùy chọn Historical Stable, Alpha và Pre-alpha trước đây cũng đều quy về Beta. Trình cài đặt sẽ dừng nếu không có bản Beta nào khả dụng. Các bản Poki Setup cũ đã cài có thể giữ hành vi kênh trước đây; hãy đọc phiên bản mà lần chạy của bạn đã chọn.

Không có Node.js 24, hoặc đang dùng Windows? Câu lệnh trên vẫn dùng được sau khi Poki Setup đã được cài: khi đó agent dùng công cụ dòng lệnh bên trong Poki Setup. Menu của Poki Setup cũng có sẵn một câu lệnh để sao chép cho agent của bạn (`Poki > Copy Prompt for Your Agent` trên máy Mac, `Settings > Use an agent` trên Windows).

Nếu GitHub trả về 403 hoặc 429 khi trình cài đặt đọc các bản phát hành của Poki, nguyên nhân thường là giới hạn theo giờ của GitHub đối với các yêu cầu ẩn danh, giới hạn này dùng chung cho mọi người trên cùng mạng của bạn. Hãy chuyển sang mạng hoặc nút proxy khác rồi chạy lại, hoặc đợi một giờ.

### Với Poki Setup

Tải Poki Setup cho macOS (`.dmg`) hoặc Windows (`.exe`, do [ZhehanZhang](https://github.com/ZhehanZhang) đóng góp) từ [bản phát hành Beta](https://github.com/JosssphZhou/poki/releases) mới nhất có chứa trình cài đặt, rồi làm theo cửa sổ hướng dẫn. Xem [Poki Setup](../desktop/README.md) để biết các bước.

### Chạy tác vụ đầu tiên của bạn

Sau khi trình cài đặt đã xác minh phiên bản đã cài và bạn đã hoàn thành các bước kết nối cục bộ và tài khoản mô hình, hãy mở Poki và gửi:

```text
Tạo một ghi chú mới trong Notes với tiêu đề "Poki Demo" gồm ba dòng sau: Milk, Eggs, Coffee. Mở ghi chú khi hoàn thành. Không thay đổi các ghi chú hiện có.
```

Kiểm tra ghi chú mới trong Notes: tiêu đề phải là "Poki Demo" và nội dung phải chứa Milk, Eggs và Coffee trên các dòng riêng biệt. Chỉ một thông báo hoàn thành thôi thì chưa phải là bằng chứng. Nếu Notes không khả dụng hoặc việc thiết lập chưa xong, hãy hoàn thành bước đó trước. Sau khi bị gián đoạn, kiểm tra xem ghi chú đã tồn tại hay chưa trước khi thử lại.

## Câu hỏi thường gặp

**Tôi có thể cài đặt Poki từ Windows không?** Có. Poki Setup cho Windows cài đặt, ghép nối và gia hạn Poki giống như phiên bản Mac. Hãy cài Apple Devices hoặc iTunes trước để PC tìm thấy iPhone. Xem [Poki Setup](../desktop/README.md).

**Sau khi cài đặt, tôi có còn cần máy tính không?** Không cần để chạy tác vụ: Poki hoạt động chỉ với chiếc iPhone. Với tài khoản Apple miễn phí, hãy giữ Poki Setup mở trên máy tính để nó gia hạn chữ ký mỗi tuần, hoặc đăng nhập tài khoản Apple trong Poki để iPhone tự gia hạn (nếu đăng nhập thất bại, hãy dùng Poki Setup trên máy tính). Xem [Những gì cần giữ chạy](../skills/install-poki/SKILL.md#what-to-keep-running).

**Tài khoản Apple miễn phí có dùng được không, và giới hạn 7 ngày là gì?** Tài khoản miễn phí dùng được, nhưng Apple chỉ ký các ứng dụng từ tài khoản đó trong 7 ngày. Trong khi đang mở, Poki Setup gia hạn Poki mỗi 6 giờ một lần khi còn từ 2 ngày trở xuống, miễn là máy tính còn thức và iPhone còn kết nối được. Nếu không gia hạn, Poki sẽ ngừng mở khi chữ ký hết hạn, vì vậy ứng dụng cảnh báo bạn trong 2 ngày cuối. Xem [Không cần tài khoản nhà phát triển trả phí](../skills/install-poki/SKILL.md#no-paid-developer-account).

**Tôi cần iPhone và iOS nào?** iOS 18 trở lên, tức iPhone XS, XR, SE (thế hệ 2) hoặc mới hơn, và iPad với iPadOS 18 trở lên. Việc kiểm thử trên máy thật tính đến nay được thực hiện trên iOS 27; iOS 18 đến 26 dùng một đường điều khiển khác chưa được kiểm thử trên iPhone thật. Xem [Kiểm chứng và các giới hạn đã biết](verification.md).

**Tôi có cần tài khoản mô hình của riêng mình không?** Có. Đăng nhập bằng gói ChatGPT Plus hoặc Pro, hoặc dán API key từ Anthropic, OpenAI, Gemini, DeepSeek, OpenRouter, hoặc OpenCode Go, hoặc dùng máy chủ tương thích OpenAI của riêng bạn. Trò chuyện với Poki còn cần một key mô hình giọng nói. Xem [Những gì bạn cần](#những-gì-bạn-cần).

**Không thấy bản cập nhật nào, ví dụ khi dùng mạng ở Trung Quốc đại lục. Phải làm sao?** Poki tìm bản cập nhật trên GitHub, và một số mạng không truy cập được GitHub hoặc chạm giới hạn 403 và 429 của GitHub. Hãy thử mạng hoặc nút proxy khác, hoặc cập nhật từ máy tính bằng Renew trong Poki Setup. Xem [Cập nhật Poki](#cập-nhật-poki).

**Poki có thay đổi mọi thứ trên iPhone của tôi không, và nó có hỏi trước không?** Poki làm việc trong các ứng dụng thật của bạn và thực hiện điều bạn yêu cầu, bao gồm gửi tin nhắn, và nội dung màn hình được gửi tới dịch vụ mô hình bạn đã thiết lập. Các thao tác thanh toán, xóa trong menu và hộp thoại xác nhận, cùng các hành động trong Wallet luôn cần bạn xác nhận. Khi không có đầy đủ chi tiết màn hình (ví dụ, một lần chạm bằng giọng nói chỉ dùng tên nút), các thao tác xóa khớp mẫu cũng yêu cầu xác nhận. Với các bước nhạy cảm khác, chẳng hạn gửi tin nhắn hoặc nhập mật khẩu, bạn chọn trong `Settings > Approvals` cách Poki hỏi, hoặc liệu nó có hỏi hay không. Xem [Sự cố đã biết](#sự-cố-đã-biết).

## Cập nhật Poki

- **Trên iPhone.** Mở trang ký và cập nhật của Poki: `Settings > Signing & Updates` trong các bản dựng hiện tại. Các bản dựng cũ hơn có thể đặt mục này trong phần Connection. Khi có bản dựng mới hơn, trang này sẽ đề xuất tải xuống và cài đặt. Nếu trang yêu cầu bạn đăng nhập trước, nghĩa là Poki đã được cài từ máy tính và iPhone chưa có tài khoản Apple của bạn. Hãy đăng nhập bằng tài khoản bạn đã dùng khi cài đặt, hoặc cập nhật từ máy tính thay thế.
- **Từ máy tính.** Renew trong Poki Setup cài đặt bản dựng mới nhất trên kênh của nó đè lên ứng dụng đã cài. Trên máy Mac, bạn cũng có thể nói với agent của mình "Update Poki on my iPhone"; kỹ năng install-poki có một đường cập nhật riêng, kiểm tra phiên bản đã cài và danh tính ký trước.
- Nếu một bản cập nhật dừng ở "Finishing the update", hãy vuốt đóng Poki trong trình chuyển đổi ứng dụng và mở lại, rồi kiểm tra phiên bản trong Settings. Nếu phiên bản không thay đổi, hãy cập nhật từ Poki Setup trên máy tính. Đừng xóa Poki để sửa lỗi cập nhật: xóa ứng dụng sẽ xóa các cuộc trò chuyện của nó.

Các kênh phát hành và cách một bản dựng đi từ Alpha lên Beta được mô tả trong [Kênh phát hành](release-channels.md).

## Thử một tác vụ

Mở Poki và gõ một tác vụ vào ô tin nhắn, chẳng hạn "Check tomorrow's weather and tell me if I need an umbrella", hoặc chạm vào một trong các ứng dụng trên trang chủ để bắt đầu một tác vụ trong ứng dụng đó. Poki làm việc trong ứng dụng trên màn hình của bạn, hiển thị từng bước trong Dynamic Island và trên Màn hình khóa, và xin phê duyệt theo cài đặt của bạn.

Bạn cũng có thể gọi Poki mà không cần mở ứng dụng: nhấn và giữ nút Tác vụ (Action Button) để nói chuyện với nó, hoặc dùng Talk to Poki và Send Task to Poki từ Shortcuts và Siri. Một tác vụ gửi theo cách đó sẽ trả lời bằng một thông báo. Trên iPhone Duo ở chế độ Split View, Poki có thể làm việc trong hai ứng dụng cạnh nhau.

> **Lưu ý:** Poki điều khiển chiếc iPhone thật của bạn. Nếu bạn yêu cầu nó gửi tin nhắn hoặc thanh toán, nó sẽ làm.

## Sự cố đã biết

- Poki thao tác chiếc iPhone thật của bạn. Nếu bạn yêu cầu nó gửi tin nhắn hoặc thanh toán, nó sẽ làm. Nội dung màn hình được gửi tới dịch vụ mô hình bạn đã thiết lập.
- Nếu bạn không thể đăng nhập tài khoản Apple trên iPhone, hãy gia hạn và cập nhật từ Poki Setup trên máy tính.
- Hỗ trợ iPhone thật mới chỉ được kiểm chứng trên các iPhone dùng giao diện tiếng Trung, ở hướng dọc. Hướng ngang không được hỗ trợ.
- Bản phát hành này chưa được kiểm thử trên iPhone thật chạy dưới iOS 27, hay trên iPad. Trên các iPhone cũ và nhỏ hơn, chú gấu ba chiều và các hiệu ứng chuyển động ở trang chủ có thể chạy nóng hơn hoặc chậm hơn. Chế độ Nguồn điện thấp (Low Power Mode) và Giảm chuyển động (Reduce Motion) sẽ hiển thị hình tĩnh của chú gấu thay thế.
- Với tài khoản Apple miễn phí, chữ ký kéo dài 7 ngày. Hãy giữ Poki Setup trên máy tính có thể kết nối tới iPhone, hoặc gia hạn thủ công trước khi hết hạn.
- Việc đọc các bản phát hành của Poki từ GitHub có thể thất bại với lỗi 403 hoặc 429, thường vì nhiều người dùng chung một mạng. Hãy chuyển mạng hoặc nút proxy và thử lại, hoặc đợi một giờ.

Thêm các giới hạn, kèm kết quả kiểm thử, có trong [Kiểm chứng và các giới hạn đã biết](verification.md).

### Bắt đầu tự động hóa sau khi khởi động lại với Clash Mi

Nếu Poki hiển thị **Turn On Loopback** sau khi iPhone khởi động lại dù Clash Mi đang kết nối, hãy dùng LocalDevVPN cho lần khởi động tự động hóa đầu tiên.

1. Mở khóa iPhone, kết nối Wi-Fi, và ngắt kết nối Clash Mi.
2. Kết nối LocalDevVPN. Trong Poki, mở **Settings > Setup** và bật **Automation** nếu nó đang tắt.
3. Mở một cuộc trò chuyện và chạm vào ô tin nhắn để bắt đầu chuẩn bị developer disk image. Trong **Settings > Advanced > Log**, đợi một mục `[runner] running` mới từ lần thử này trước khi chuyển VPN.
4. Giữ **Automation** bật. Ngắt kết nối LocalDevVPN và kết nối lại Clash Mi. Yêu cầu Poki tính 37 × 19 trong Calculator và kiểm tra Calculator hiển thị 703.

Nếu Poki hiển thị **Enter Your Passcode Next** khi bạn bật tự động hóa hoặc chạy tác vụ đầu tiên, hãy chạm **Continue**. Nếu Poki đang chờ xác nhận mà cảnh báo không xuất hiện, mở **Settings > Setup** và chạm **Continue** tại đó. Nhập mật mã iPhone khi iOS yêu cầu.

Poki cần kết nối tới các dịch vụ nhà phát triển của iPhone để gắn (mount) developer disk image sau khi khởi động lại. Khi image đã được gắn, Poki có thể dùng nó cho tự động hóa cục bộ. Nếu lời nhắc quay lại sau lần khởi động lại tiếp theo, hãy lặp lại các bước này. Nếu việc chuyển đổi vẫn thất bại, mở **Settings > Advanced > Diagnostics** và so sánh kết quả **Reflected RemotePairing** với từng VPN.

## Lộ trình

Phần này liệt kê các hướng đi, không phải ngày tháng. Các tính năng đã phát hành được ghi trong [CHANGELOG.md](../CHANGELOG.md).

**Đã phát hành trong 0.4 Beta**

- Ứng dụng iPhone chạy tác vụ mà không cần máy tính sau khi thiết lập, với phê duyệt trên Màn hình khóa và trong Dynamic Island.
- Cài đặt bằng agent của bạn hoặc Poki Setup trên máy Mac hoặc Windows PC, dùng tài khoản Apple miễn phí.
- Điều khiển gốc trên iOS 27 trở lên, cùng các tác vụ web trong trình duyệt tích hợp của Poki.
- Một trang chủ với chú gấu ba chiều, trò chuyện bằng giọng nói, nút Tác vụ (Action Button), các cuộc trò chuyện đã lưu trữ, iPhone Duo Split View, kích thước giao diện điều chỉnh được, và chế độ tối.

**Đang thực hiện**

- Cung cấp bản cập nhật đáng tin cậy hơn và xử lý cập nhật thống nhất.
- Giao diện với nhiều ngôn ngữ hơn.

**Đã lên kế hoạch**

- Thêm nhiều iPhone, phiên bản iOS và ngôn ngữ màn hình được kiểm chứng trên thiết bị thật.
- Thêm nhiều nhà cung cấp mô hình.

## Các công cụ khác

[Poki MCP](poki-mcp.md) kết nối agent của một máy tính tới một iPhone hoặc iOS Simulator; công cụ đời đầu này không còn được cập nhật nữa.

[Poki Agent](poki-mcp.md#try-a-task-with-poki-agent) là agent trên terminal với các kênh iMessage và Telegram; cách thiết lập và sử dụng vẫn nằm trong hướng dẫn được liên kết.

## Tuyên bố miễn trừ trách nhiệm

Poki là một dự án mã nguồn mở độc lập. Dự án không liên kết với, và không được chứng thực bởi, Apple, OpenAI, hay nhà phát triển của bất kỳ ứng dụng hoặc trang web nào mà nó thao tác. iPhone là nhãn hiệu của Apple Inc.

Việc tự động hóa các ứng dụng và trang web của bên thứ ba có thể vi phạm điều khoản dịch vụ của họ. Hãy tự quyết định liệu có nên dùng Poki với một dịch vụ cụ thể hay không. Bạn chịu trách nhiệm về những gì nó làm trên thiết bị và tài khoản của bạn, bao gồm tin nhắn nó gửi, thay đổi nó thực hiện, và mọi hạn chế tài khoản phát sinh.

Poki được cung cấp "nguyên trạng", không có bảo hành, như quy định trong giấy phép AGPL-3.0.

## Giấy phép

Mã nguồn của Poki là mã nguồn mở theo [giấy phép AGPL-3.0-only](../LICENSE).

Chú gấu Poki, biểu tượng ứng dụng, và các tác phẩm nghệ thuật khác của Poki không thuộc giấy phép đó. Bạn có thể dùng ảnh chụp màn hình để viết về Poki; một fork cần có tên và tác phẩm nghệ thuật riêng. Xem [BRAND.md](../BRAND.md).

Copyright (c) 2026 Joseph Zhou (周瑟夫) and contributors. Các phụ thuộc mã nguồn mở và tài sản của bên thứ ba giữ nguyên giấy phép tương ứng của chúng; xem [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md). Để đóng góp, xem [CONTRIBUTING.md](../CONTRIBUTING.md).
