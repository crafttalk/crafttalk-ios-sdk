**SDK для подключения виджета чата CraftTalk для iOS:**

**Поддерживаемая минимальная версия**

iOS 9.0

**Шаг 1. Установление зависимости**

На данный момент SDK необходимо добавлять в проект "вручную".
    
**Шаг 2. Использование**
1. Организуется web-страница с подключенным виджетом веб-чата и, при необходимости, с передачей данных пользователя в виджет. Информация о подключении виджета и возможностях его настройки доступна в "Техническом описании" платформы CraftTalk.

2. Push notifications
    
    Для пуш-уведомлений используется сервис Firebase, его необходимо подключить в хост-приложение, а также не забыть добавить соответствующие capabilities.
    После настройки Firebase в методе messaging(:_didReceiveRegistrationToken) нужно добавить следующую строку:
    
     ```
     func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String) {
         CTChat.shared.saveFCMToken(fcmToken) <--- Необходимо добавить
     }
    
3. Настройка URL и других параметров

    В Info.plist приложения хоста добавить следующие параметры:
    ```
    <key>CTChatBaseURL</key>
    <string>ссылка</string>
    <key>CTChatNamespace</key>
    <string>namespace</string>
    <key>CTSalt</key>
    <string>соль</string>
   ```
   
    CTChatBaseURL - ссылка на хост.
    CTChatNamespace - namespace или идентификатор канала.
    CTSalt - соль для хэширования пользователя.
    
4. Инициализация библиотеки
    
    В метод application(_:didFinishLaunchingWithOptions:) класса AppDelegate добавить:
    ```
    CTChat.shared.configure()
    
5. Создание пользователя
    
    Приложению хосту нужно предоставить объект CTVisitor до показа чата, чтобы пользователь зарегистрировался в системе.
    ```
    CTChat.shared.registerVisitor(.init(firstName: "Имя", lastName: "Фамилия"))

6. Использование в storyboard:

    ```
    Для созданного UIViewController в storyboard указать в Identity inspector класс CTChatViewController. Никаких дополнительных view добавлять не нужно.
    
7. Инициализация CTChatViewController через код:
    
    CTViewController можно инициализовать через код 

    ```
    CTChatViewController()
    
8.  Для работы SSL Pinning необходимо добавить сертификат с именем **CTCertificate** с расширением **.crt**, **.der** или **.cer** в main bundle приложения. 

9. При создании и отображении класса CTChatViewController убедиться, что другие классы ссылаются на него по слабой ссылке или не ссылаются вовсе, так как при наличии в памяти нескольких CTChatViewController каждый экземпляр чата отправляет /start при открытии CTChatViewController

**Пример приложения**

Пример находится в Example

**Permission**

Для работы с файлами необходимо приложению-хосту установить следующие разрешения и запросить соответствующие:

- Privacy - Camera Usage Description
- Privacy - Photo Library Additions Usage Description
- Privacy - Photo Library Usage Description
