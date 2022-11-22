# Face Detection

## Authors:

- Rijubrata Bhaumik, Intel Corporation
- Tuukka Toivonen, Intel Corporation
- Eero Häkkinen, Intel Corporation

## Participate
- github.com/riju/faceDetection/issues/

## Introduction

This document describes a proposal to the WebRTC WG. At this stage, this proposal has not been accepted by the WG.
Face detection is the process of detecting human faces in a given scene and distinguishing them from other objects. There are multiple ways to perform face detection on the Web. Libraries and machine learning (ML) frameworks (with WebAssembly and WebGL backend) exist, both proprietary and open source, which can perform  face detection either in client within the browser or using a vendor cloud service. Computation in vendor cloud adds latencies depending on network speed and adds dependency to third party service. 

[Shape Detection API has a FaceDetector](https://wicg.github.io/shape-detection-api/) which enables Web applications to use a system provided face detector, but it requires image data to be provided by the Web app itself. It surely helps that it works on images to detect faces, but from a video conference perspective, it means the app would first need to capture frames from a camera and then feed them as input to the Shape Detection API. Many platforms offer a camera API which can perform face detection directly on image frames from the system camera. Cameras run a face detection algorithm by default to make their 3A algorithms work better. Both Windows and ChromeOS offer native platforms APIs to hook into those algorithms and offer performant face detection to the Web.


## Goals 

* Face detection API should be split into two parts: first to allow enabling face detection on [MediaStreamTrack](https://www.w3.org/TR/mediacapture-streams/#dom-mediastreamtrack) source, and then to define the description of detected faces in WebCodecs [VideoFrame](https://www.w3.org/TR/webcodecs/#videoframe-interface)s.

* The description of faces in frames should extend the [VideoFrameMetadata](https://www.w3.org/TR/webcodecs/#dictdef-videoframemetadata) and the description can be supplemented or replaced by Web applications.

* Face detection API should return information on detected faces and landmark as available on current platform APIs. For faces it should return bounding box and for landmarks the center point of the landmarks.

* Face descriptions should allow face tracking but not face recognizion or correlation of faces between different sources.

* Face detection API should work with [TransformStream](https://developer.mozilla.org/en-US/docs/Web/API/TransformStream).

* Face descriptions could be used as an input to various algorithms like background blur, eye gaze correction, face framing, etc. Face detection minimizes the surface area that other algorithms need to process for a faster implementation. It should be easy to use face detection API along with a custom eye gaze correction or the Funny Hats feature from a ML framework by passing the face coordinates.

* Facial landmarks like *eyes* and *mouth* should be detected if there's support in the platform and user enables it.

* The API should be as minimal as possible, while still supporting current platforms and allowing applications to ask for the minimum amount of extra computation that they need.

## Non-goals

* Face detection API must not support facial expressions. Many platforms support *blink* and *smile* and ML frameworks support a diverse set of expressions, typically *anger*, *disgust*, *fear*, *happiness*, *sadness*, *surprise*, and *neutral*.  [Many people](https://www.w3.org/2021/11/24-webrtc-minutes.html#t04) felt that expressions are too subjective and there's a concern of misdetecting expressions.

* Face detection API does not need to return a mesh corresponding to the detected faces. Even though TensorFlow returns a 468-landmark FaceMesh and most DNNs can return something similar, mesh is not supported on any platforms presently, and for the sake of simplicity, it is excluded for now. However, in the long term it may be appropriate to extend the face detection API to be able to also return mesh-based face detection results. This is left for future work.

## Face detection API

### Metadata

The API consists of two parts: first, metadata which describes the faces available in video frames. The metadata could be also set by user by creating a new video frame (modifying video frame metadata in existing frames is not allowed by the specification). The metadata could be used by WebCodecs encoders to improve video encoding quality, for example by allocating more bits to face areas in frames. As the encoding algorithms are not specified in standards, also the exact way how the facial metadata is used is not specified.

```js
partial dictionary VideoFrameMetadata {
  sequence<HumanFace> humanFaces;
};

dictionary HumanFace {
  long              id;
  float             probability;
  DOMRectReadOnly   boundingBox;
  HumanFaceLandmark leftEye;
  HumanFaceLandmark rightEye;
  HumanFaceLandmark mouth;
};

dictionary HumanFaceLandmark {
  Point2D           centerPoint;
};

```

### Constraints

The second part consists of constraints to `getUserMedia()` or `applyConstrains()` which are used to negotiate and enable the desired face detection mode. Often, camera drivers run already internally face detection for 3A, so enabling face detection might just make the results available to Web applications. The corresponding members are added also to media track settings and capabilities. 

```js
partial dictionary MediaTrackSupportedConstraints {
  boolean humanFaceDetectionMode = true;
  boolean humanFaceLandmarkDetectionMode = true;
};

partial dictionary MediaTrackCapabilities {
  sequence<DOMString> humanFaceDetectionMode;
  sequence<DOMString> humanFaceLandmarkDetectionMode;
};

partial dictionary MediaTrackConstraintSet {
  ConstrainDOMString humanFaceDetectionMode;
  ConstrainDOMString humanFaceLandmarkDetectionMode;
};

partial dictionary MediaTrackSettings {
  DOMString humanFaceDetectionMode;
  DOMString humanFaceLandmarkDetectionMode;
};

enum ObjectDetectionMode {
  "none",          // Face or landmark detection is not needed
  "center-point",  // Center point of the detected object is returned
  "bounding-box",  // Bounding box of the detected object is returned
};

```

## Using the face detection API

### Metadata

The first part of the API adds a new member `humanFaces` of type sequence of `HumanFace` into WebCodecs [`VideoFrameMetadata`](https://www.w3.org/TR/webcodecs/#dictdef-videoframemetadata) which provides information of the detected faces in the frame. In `HumanFace`, the member `id` is used to track faces between frames: the same `id` of a face between different frames indicates that it is the same face under tracking. However, it is specifically required that it must not be possible to correlate faces between different sources or video sequences by matching the `id` between them. If host uses face recognizion to track faces, it must assign a random integer to `id` between sequences to avoid privacy issues. `probability` is the probability that the returned face is in fact a human face and not a false detection.

The member `boundingBox` provides the enclosing bounding box for the face.

The members `leftEye`, `rightEye`, and `mouth` provide information on facial features belonging to the detected face. Currently this includes the center point for eyes and mouth, but we define a separate dictionary `HumanFaceLandmark` to allow extending it easily later on. 

The coordinates in the members `boundingBox` and `centerPoint` of the detected faces and landmarks are defined similarly as in the
[`pointsOfInterest`](https://w3c.github.io/mediacapture-image/#points-of-interest)
member in [`MediaTrackSettings`](https://w3c.github.io/mediacapture-image/#dom-mediatracksettings-pointsofinterest)
with the exception that the coordinates may also lie outside of the frame since a detected face could be
partially (or in special cases even fully) outside of the visible image.
A coordinate is interpreted to represent a location in a normalized square space. The origin of
coordinates (x,y) = (0.0, 0.0) represents the upper leftmost corner whereas the (x,y) =
(1.0, 1.0) represents the lower rightmost corner relative to the rendered frame: the x-coordinate (columns) increases rightwards and the y-coordinate (rows) increases downwards.

### Constraints

New members are added to capabilities, constraints, and settings for Web applications to enable and control face and face landmark detection with `getUserMedia()` and `applyConstraints()` and to query capabilities of face detection with `getCapabilities()` methods. Web applications should not ask more facial metadata than what they need to limit computation. For example, if an applications is content with just a face bounding box, it should set the constraint `humanFaceLandmarkDetectionMode` to `"none"`.

The enumeration constraints `humanFaceDetectionMode` and `humanFaceLandmarkDetectionMode` set the level of detection needed for human faces and their landmarks, respectively. These settings can be one of the enumeration values in `ObjectDetectionMode`. When `humanFaceDetectionMode` is `"bounding-box"`, user agent must attempt face detection and set the metadata in video frames correspondingly. When the setting is `"none"`, face description metadata (including landmarks) is not set. Similarly, when `humanFaceLandmarkDetectionMode` is `"none"`, the landmarks (ie. members `leftEye`, `rightEye`, and `mouth` in dictionary `HumanFace`) are not set. When the setting is `"center-point"` and face detection is enabled, the user agent must attempt to detect face landmarks and set the location information in the members of type `HumanFaceLandmark` accordingly. 

For now, `"center-point"` must not be supported for `humanFaceDetectionMode` and `"bounding-box"` must not be supported for `humanFaceLandmarkDetectionMode` due to limitations in current platform APIs. Furthermore, if face detection mode is `"none"`, also landmark detection setting must be the same `"none"` because without face detection results the landmark data can not be set either.

## Platform Support 


| OS               | API              | face detection|
| ------------- |:-------------:| :-----:|
| Windows      | Media Foundation|   [KSPROPERTY_CAMERACONTROL_EXTENDED_FACEDETECTION ](https://docs.microsoft.com/en-us/windows-hardware/drivers/stream/ksproperty-cameracontrol-extended-facedetection?redirectedfrom=MSDN)|
| ChromeOS/Android      | Camera HAL3 | [STATISTICS_FACE_DETECT_MODE_FULL  ](https://developer.android.com/reference/android/hardware/camera2/CameraMetadata#STATISTICS_FACE_DETECT_MODE_FULL)[STATISTICS_FACE_DETECT_MODE_SIMPLE ](https://developer.android.com/reference/android/hardware/camera2/CameraMetadata#STATISTICS_FACE_DETECT_MODE_SIMPLE)|
| Linux | GStreamer      |    [facedetect ](https://gstreamer.freedesktop.org/data/doc/gstreamer/head/gst-plugins-bad/html/gst-plugins-bad-plugins-facedetect.html)|
| macOS| Core Image Vision|    [CIDetectorTypeFace ](https://developer.apple.com/documentation/coreimage)[VNDetectFaceRectanglesRequest](https://developer.apple.com/documentation/vision/vndetectfacerectanglesrequest)|


## Performance

Face detection, using the proposed Javascript API, was compared to several other alternatives in power usage.
The results were normalized against base case (viewfinder only, no face detection) and are shown in the following chart.

![Package Power Consumption](images/face-detection-ptat-fd15fps-rel.png)

Javacript test programs were created to capture frames and to detect faces at VGA resolution (640x480) at 15 fps. The tests were run on Intel Tigerlake running Windows 11. A test run length was 120 seconds (2 minutes) with 640x480 pixel frame resolution. 

## User research

* TEAMS : Supportive, but [not supportive of adding facial expressions](https://www.w3.org/2021/11/24-webrtc-minutes.html#t04) and doubtful on the accuracy of emotion analysis.

*Agreed, facial expressions are part of [Non-goals](https://github.com/riju/faceDetection/blob/main/explainer.md#non-goals) for this API*


* MEET : Supportive, but many applications might not be using rectangle-bounding box, mask/contour more useful.

*Currently common platforms such as ChromeOS, Android, and Windows support [system APIs](https://github.com/riju/faceDetection/blob/main/explainer.md#platform-support) which return only face bounding box and landmarks, not accurate contour, and therefore initial implementations are expected to support only bounding-box (ie. a contour with maximum of four points). We would keep the API extensible, so that proper contour support can be added in future. A few [use-cases for bounding-box face detection](https://github.com/riju/faceDetection/blob/main/explainer.md#key-scenarios) are listed.*


* Zoom : 

## Key scenarios

Currently common platforms such as ChromeOS, Android, and Windows support system APIs which return face bounding box and landmarks. This information can be used as the major building block in several scenarios such as:

* Auto-mute: a videoconferencing application can automatically mute microphone or blank camera image if user (face) presence is not detected.

* Face framing: application can use pan-tilt-zoom interface to zoom close up to user's face, or if pan-tilt-zoom is not available, crop the image digitally appropriately.

* Face enhancement: application can apply various image enhancement filters to user's face. The filters may be either designed exclusively to faces, or when it is desired to save computation, background can be excluded from the filtering.

* Funny Hats: application may want to render augmented reality on top of user faces by drawing features such as glasses or a hat. For accurate rendering, facial landmarks would be preferred.

* Video encoding: many video encoders can allocate higher amount of bits to given locations in frames. Face bounding boxes can be used to increase the visual quality of faces at the cost of lower background quality.

* Neural networks: these can be used to derive accurate face contours, recognize faces, or extract other facial information. However, these are typically slow and heavyweight algorithms which are too burdensome to apply to entire images. A known face bounding box allows applying an algorithm only to the relevant part of images.


## Example

```js
// main.js:
// Check if face detection is supported by the browser
const supports = navigator.mediaDevices.getSupportedConstraints();
if (supports.humanFaceDetectionMode) {
  // Browser supports face detection.
} else {
  throw('Face detection is not supported');
}

// Open camera with face detection enabled
const stream = await navigator.mediaDevices.getUserMedia({
  video: { humanFaceDetectionMode: 'bounding-box' }
});
const [videoTrack] = stream.getVideoTracks();

// Use a video worker and show to user.
const videoElement = document.querySelector("video");
const videoGenerator = new MediaStreamTrackGenerator({kind: 'video'});
const videoProcessor = new MediaStreamTrackProcessor({track: videoTrack});
const videoSettings = videoTrack.getSettings();
const videoWorker = new Worker('video-worker.js');
videoWorker.postMessage({
  videoReadable: videoProcessor.readable,
  videoWritable: videoGenerator.writable
}, [videoProcessor.readable, videoGenerator.writable]);
videoElement.srcObject = new MediaStream([videoGenerator]);
videoElement.onloadedmetadata = event => videoElement.play();

// video-worker.js:
self.onmessage = async function(e) {
  const videoTransformer = new TransformStream({
    async transform(videoFrame, controller) {
      for (const face of videoFrame.metadata().humanFaces || []) {
        console.log(`Face @ (${face.boundingBox.left},` +
                            `${face.boundingBox.top},` +
                            `${face.boundingBox.right},` +
                            `${face.boundingBox.bottom})`);
      }
      controller.enqueue(videoFrame);
    }
  });
  e.data.videoReadable
  .pipeThrough(videoTransformer)
  .pipeTo(e.data.videoWritable);
}
```

## Stakeholder Feedback / Opposition

[Implementors and other stakeholders may already have publicly stated positions on this work. If you can, list them here with links to evidence as appropriate.]

- [Firefox] : No signals
- [Safari] : No signals

[If appropriate, explain the reasons given by other implementors for their concerns.]

## References & acknowledgements

Many thanks for valuable feedback and advice from:

- Bernard Aboba
- Harald Alvestrand
- Jan-Ivar Bruaroey
- Youenn Fablet
- Dominique Hazael-Massieux

## Disclaimer

Intel is committed to respecting human rights and avoiding complicity in human rights abuses. See Intel's Global Human Rights Principles. Intel's products and software are intended only to be used in applications that do not cause or contribute to a violation of an internationally recognized human right.

Intel technologies may require enabled hardware, software or service activation.

No product or component can be absolutely secure.

Your costs and results may vary.

© Intel Corporation
