//  Label StoreMax
//
//  Created by Anthony Gordon.
//  2026, WooSignal Ltd. All rights reserved.
//

//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.

import 'package:woosignal/models/response/woosignal_app.dart';

class AppHelper {
  AppHelper._privateConstructor();

  static final AppHelper instance = AppHelper._privateConstructor();
  WooSignalApp? appConfig;

  /// TRYON LANKA: true only when the store settings loaded from WooSignal.
  /// When false the app opens in offline Try-On mode instead of the shop.
  bool storeConnected = false;
}
