import '../direction/card_swiper_direction.dart';

sealed class ControllerEvent {
  const ControllerEvent();
}

class ControllerSwipeEvent extends ControllerEvent {
  final CardSwiperDirection direction;
  const ControllerSwipeEvent(this.direction);
}

// class ControllerUndoEvent extends ControllerEvent {
//   const ControllerUndoEvent();
// }

class ControllerMoveEvent extends ControllerEvent {
  final int index;
  const ControllerMoveEvent(this.index);
}
