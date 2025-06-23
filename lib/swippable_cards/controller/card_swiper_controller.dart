import 'dart:async';

import '../direction/card_swiper_direction.dart';
import 'controller_event.dart';

// /// A controller that can be used to trigger swipes on a CardSwiper widget.
// class CardSwiperController {
//   final _eventController = StreamController<ControllerEvent>.broadcast();

//   /// Stream of events that can be used to swipe the card.
//   Stream<ControllerEvent> get events => _eventController.stream;

//   /// Swipe the card to a specific direction.
//   void swipe(CardSwiperDirection direction) {
//     _eventController.add(ControllerSwipeEvent(direction));
//   }

//   // Undo the last swipe
//   void undo() {
//     _eventController.add(const ControllerUndoEvent());
//   }

//   // Change the top card to a specific index.
//   void moveTo(int index) {
//     _eventController.add(ControllerMoveEvent(index));
//   }

//   Future<void> dispose() async {
//     await _eventController.close();
//   }
// }

class CardSwiperController {
  final _eventController = StreamController<ControllerEvent>.broadcast();

  int _currentIndex = 0; // Track the current index.
  int _cardsCount = 0;
  void setCardsCount(int count) {
    _cardsCount = count;
  }

  // Getter to access the current index
  int get currentIndex => _currentIndex;
  int get cardsCount => _cardsCount;

  bool get isAtLastCard => _currentIndex == _cardsCount - 1;

  /// Stream of events that can be used to swipe the card.
  Stream<ControllerEvent> get events => _eventController.stream;

  // Swipe the card to a specific direction.
  void swipe(CardSwiperDirection direction) {
    _eventController.add(ControllerSwipeEvent(direction));
  }

  // Undo the last swipe
  // void undo() {
  //   _eventController.add(const ControllerUndoEvent());
  // }

  // Change the top card to a specific index.
  void moveTo(int index) {
    if (index >= 0) {
      _currentIndex = index; // Update current index.
      _eventController
          .add(ControllerMoveEvent(index)); // Trigger swipe to the new index.
    }
  }

  Future<void> dispose() async {
    await _eventController.close();
  }
}
