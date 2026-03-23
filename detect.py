"""
YOLO Object Detection Script with optimized settings.

Usage:
    python detect.py --source image.jpg
    python detect.py --source video.mp4
    python detect.py --source 0  # webcam
"""

import argparse
import cv2
import numpy as np
from pathlib import Path

try:
    from ultralytics import YOLO
except ImportError:
    raise ImportError("Install ultralytics: pip install ultralytics")


def parse_args():
    parser = argparse.ArgumentParser(description="YOLO Object Detection")
    parser.add_argument("--source", type=str, required=True,
                        help="Path to image, video, or camera index (0)")
    parser.add_argument("--model", type=str, default="yolo11n.pt",
                        help="Model path or name (default: yolo11n.pt)")
    parser.add_argument("--conf", type=float, default=0.25,
                        help="Confidence threshold (default: 0.25)")
    parser.add_argument("--iou", type=float, default=0.45,
                        help="NMS IoU threshold (default: 0.45)")
    parser.add_argument("--imgsz", type=int, default=640,
                        help="Input image size (default: 640)")
    parser.add_argument("--save", action="store_true",
                        help="Save annotated output")
    parser.add_argument("--show", action="store_true",
                        help="Display results in window")
    return parser.parse_args()


def draw_detections(frame, results):
    """Draw bounding boxes with clean visualization (no filled overlay)."""
    for result in results:
        boxes = result.boxes
        for box in boxes:
            x1, y1, x2, y2 = map(int, box.xyxy[0])
            conf = float(box.conf[0])
            cls_id = int(box.cls[0])
            cls_name = result.names[cls_id]

            # Color based on class (consistent per class)
            color = _class_color(cls_id)

            # Draw rectangle outline only (thickness=2, no fill)
            cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)

            # Label with background
            label = f"{cls_name} {conf:.2f}"
            (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.6, 1)
            cv2.rectangle(frame, (x1, y1 - th - 8), (x1 + tw + 4, y1), color, -1)
            cv2.putText(frame, label, (x1 + 2, y1 - 4),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1,
                        cv2.LINE_AA)

    return frame


def _class_color(cls_id):
    """Generate a distinct color for each class ID."""
    np.random.seed(cls_id)
    return tuple(int(c) for c in np.random.randint(50, 255, size=3))


def run_detection(args):
    model = YOLO(args.model)

    # Run inference with optimized parameters
    results = model.predict(
        source=args.source,
        conf=args.conf,
        iou=args.iou,
        imgsz=args.imgsz,
        verbose=False,
    )

    # Determine if source is image or video
    source_path = Path(args.source) if not args.source.isdigit() else None
    is_image = source_path and source_path.suffix.lower() in {
        ".jpg", ".jpeg", ".png", ".bmp", ".tiff", ".webp"
    }

    if is_image:
        frame = cv2.imread(str(source_path))
        frame = draw_detections(frame, results)

        if args.save:
            out_path = source_path.with_name(f"{source_path.stem}_detected{source_path.suffix}")
            cv2.imwrite(str(out_path), frame)
            print(f"Saved: {out_path}")

        if args.show:
            cv2.imshow("Detection", frame)
            cv2.waitKey(0)
            cv2.destroyAllWindows()

        # Print summary
        for result in results:
            for box in result.boxes:
                cls_name = result.names[int(box.cls[0])]
                conf = float(box.conf[0])
                print(f"  {cls_name}: {conf:.2f}")
    else:
        # Video/webcam - use YOLO's built-in streaming
        results = model.predict(
            source=args.source,
            conf=args.conf,
            iou=args.iou,
            imgsz=args.imgsz,
            stream=True,
            verbose=False,
        )
        for result in results:
            frame = result.orig_img.copy()
            frame = draw_detections(frame, [result])

            if args.show:
                cv2.imshow("Detection", frame)
                if cv2.waitKey(1) & 0xFF == ord("q"):
                    break

        cv2.destroyAllWindows()


if __name__ == "__main__":
    args = parse_args()
    run_detection(args)
