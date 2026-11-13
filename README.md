**SDK для подключения виджета чата CraftTalk для iOS**

Разработка: [сборка, тесты и CI](docs/ci-and-testing.md).

**Поддерживаемая минимальная версия**

Исторически заявлена iOS 9.0; текущая доработка не повышает минимальную версию.
Запуск проверялся на iOS 18.6 и 27.2; совместимость с iOS 9 не подтверждена.

**Шаг 1. Установление зависимости**

Добавьте каталог `CTChat` исходниками в target приложения либо подключите пакет
через Swift Package Manager, продукт `CraftTalk` (`import CraftTalk`).

**Шаг 2. Использование**

1. Организуйте web-страницу с подключённым виджетом веб-чата. Информация о подключении
   и настройке виджета доступна в «Техническом описании» платформы CraftTalk.

2. Push notifications

   Для пуш-уведомлений используется сервис Firebase, его необходимо подключить
   в хост-приложение, а также не забыть добавить соответствующие capabilities.
   После настройки Firebase в метод `messaging(_:didReceiveRegistrationToken:)`
   нужно добавить вызов `CTChat.shared.saveFCMToken(fcmToken)`:

   ```swift
   func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String) {
       CTChat.shared.saveFCMToken(fcmToken)
   }
   ```

3. В `Info.plist` приложения добавьте адрес сервера, namespace канала и соль:

   ```xml
   <key>CTChatBaseURL</key>
   <string>https://chat.example.com</string>
   <key>CTChatNamespace</key>
   <string>channel-id</string>
   <key>CTSalt</key>
   <string>your-salt</string>
   ```

   `CTChatBaseURL` — ссылка на хост.
   `CTChatNamespace` — namespace или идентификатор канала.
   `CTSalt` — соль для хэширования пользователя.

4. В `application(_:didFinishLaunchingWithOptions:)` настройте SDK:

   ```swift
   CTChat.shared.configure()
   ```

5. До показа чата зарегистрируйте посетителя с постоянным идентификатором:

   ```swift
   CTChat.shared.registerVisitor(CTVisitor(firstName: "Имя", lastName: "Фамилия", uuid: "visitor-id"))
   ```

   При корректном Info.plist настройки готовы сразу после возврата из `configure()`
   или успешного `configure(security:)`: посетителя можно создавать без задержки.
   Автоматический hash использует `CTSalt`; явно переданный `hash` сохраняется.
   В `customProperties` используйте собственные ключи: стандартные поля посетителя
   имеют приоритет, включая `uuid` и `hash`.
   [Ошибки и ограничения настройки](docs/security-configuration.md#ограничения-инициализации).

6. В storyboard задайте контроллеру класс `CTChatViewController` в Identity inspector.
   Дополнительные view не нужны. Для создания через код:

   ```swift
   let chat = CTChatViewController(nibName: nil, bundle: nil)
   ```

7. В старом режиме `configure()` для pinning добавьте в bundle приложения серверный
   сертификат `CTCertificate.cer`, `.der` или `.crt` в бинарном формате DER.
   Он сравнивается с сертификатом сервера; это не добавление доверенного корня.

8. Не удерживайте несколько экземпляров `CTChatViewController`: каждый запускает
   собственный веб-чат и отправляет `/start` при открытии.

Push-регистрация сохраняет прежнее поведение: при обработке сообщений моста
SDK планирует отдельный запрос через пять секунд, если токен непустой.
Посетитель должен быть зарегистрирован заранее. Запрос использует токен и UUID
на момент планирования; последующая смена данных его не отменяет.
[Подробности контракта и ограничения](docs/security-configuration.md#посетитель-и-push).

**Дополнительные корневые сертификаты и редиректы**

Вместо `configure()` можно явно выбрать новый режим:

```swift
let security = CTSecurityConfiguration(
    trustedRootsByHost: ["chat.example.com": [rootDER]],
    allowedRedirectHosts: ["chat.example.com"]
)
try CTChat.shared.configure(security: security)
```

`rootDER` — данные корневого CA из ресурсов приложения. Системное доверие сохраняется;
корни и разрешённые переходы настраиваются независимо. Пустая конфигурация использует
только системные корни. Новый режим не применяет `CTCertificate`.

[Загрузка сертификата, обработка ошибок и ограничения](docs/security-configuration.md).

**Пример приложения**

Откройте `Example/Chat.xcworkspace`. Пример использует новый режим с системным доверием.

**Permission**

Для работы с файлами приложению нужны описания разрешений и запрос доступа:

- Privacy — Camera Usage Description (`NSCameraUsageDescription`)
- Privacy — Photo Library Additions Usage Description (`NSPhotoLibraryAddUsageDescription`)
- Privacy — Photo Library Usage Description (`NSPhotoLibraryUsageDescription`)
