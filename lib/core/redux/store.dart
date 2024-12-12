import 'package:chatterloop_app/core/redux/actions.dart';
import 'package:chatterloop_app/core/redux/state.dart';
import 'package:redux/redux.dart';

ReduxActions reducers = ReduxActions();

AppState _setUserAuth(AppState state, dynamic action) {
  return state.copyWith(
      authState: reducers.setUserAuth(state, action).userAuth);
}

final appReducer = combineReducers<AppState>(
    [TypedReducer<AppState, dynamic>(_setUserAuth).call]);

class StateStore {
  final Store<AppState> store =
      Store<AppState>(appReducer, initialState: AppState());
}
