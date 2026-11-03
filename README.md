# meowmail

A Discord-style Gmail client for iPhone and macOS. It has no server: the app
talks directly to Gmail, and sign-in tokens stay in each device's Keychain.

## 1. Google Cloud setup (once)

1. Go to https://console.cloud.google.com and create a project.
2. Under **APIs & Services > Library**, enable the **Gmail API**.
3. Under **Google Auth Platform**, set up the consent screen as **External**.
4. Under **Data Access**, add the scope `https://www.googleapis.com/auth/gmail.modify`.
5. Under **Audience**, choose **Publish app** so it's "In production". Without
   this, sign-ins expire every 7 days. Skip Google's verification; it's only
   needed for public apps.
6. Under **Clients**, create a client of type **iOS** with bundle ID
   `dev.jaderowland.meowmail`, then copy the client ID.

On sign-in Google shows an "unverified app" warning. Choose **Advanced**, then
**Go to meowmail**.

## 2. Run on your Mac

You need Xcode, which is free on the Mac App Store. To look around before doing
the Google setup, see [Trying it without signing in](#trying-it-without-signing-in).

1. Double-click `MeowMail.xcodeproj` in Finder, or run this from the project
   folder:

       open MeowMail.xcodeproj

2. In the bar at the top of the Xcode window, check that it says **MeowMail** and
   **My Mac**. If it shows an iPhone, click the name and choose **My Mac**.
3. Press the **▶** button or **Cmd+R**. The app builds and its window opens.
4. On first launch, paste the client ID from step 1.6, then connect your Gmail
   accounts.

To stop the app, press the **■** button or **Cmd+.** in Xcode.

### Install it as a normal app

To keep meowmail in your Applications folder so you can open it without Xcode,
run this from the project folder:

    ./install-mac.sh

It builds a release copy, puts it in `/Applications/meowmail.app`, and opens it.
After that, open it from Launchpad, Spotlight, or the Dock like any other app.
To update it after changing the code, run the script again. Your accounts and
settings stay.

## 3. Run on your iPhone

1. Add your Apple account in **Xcode > Settings > Accounts**.
2. Select the MeowMail target, open **Signing & Capabilities**, and choose your team.
3. If the bundle ID is rejected as taken, change it there and update the Google
   client to match.
4. Connect your iPhone, turn on Developer Mode, select it in Xcode, and press Run.
5. On the iPhone, trust your developer profile under
   **Settings > General > VPN & Device Management**.

With a free Apple account, the iPhone install stops opening after 7 days. Press
Run again to renew it; your data stays.

## Trying it without signing in

Sample data lets you try the app without a Google client ID.

1. In Xcode, choose **Product > Scheme > Edit Scheme**.
2. Select **Run** on the left and open the **Arguments** tab.
3. Under **Arguments Passed On Launch**, click **+** and enter `-demo`.
4. Close the window and press **Cmd+R**.

To go back to your real mail, untick `-demo` in the same list.

## Tests

    xcodebuild test -project MeowMail.xcodeproj -scheme MeowMail -destination 'platform=macOS'
