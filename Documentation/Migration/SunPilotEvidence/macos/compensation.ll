; ModuleID = '/Users/sessions/conductor/workspaces/AstronomyKit/tallinn/.context/issue83/macos-isolated/compensation.ll'
source_filename = "/Users/sessions/conductor/workspaces/AstronomyKit/tallinn/.context/issue83/macos-isolated/compensation.ll"
target datalayout = "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
target triple = "arm64-apple-macosx27.0.0"

@__swift_reflection_version = linkonce_odr hidden constant i16 3
@llvm.used = appending global [2 x ptr] [ptr @"$s12compensation14compensatedAddyySdz_SdzSdtF", ptr @__swift_reflection_version], section "llvm.metadata"

; Function Attrs: mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: readwrite)
define swiftcc void @"$s12compensation14compensatedAddyySdz_SdzSdtF"(ptr captures(none) dereferenceable(8) %0, ptr captures(none) dereferenceable(8) %1, double %2) #0 {
entry:
  %3 = load double, ptr %0, align 8
  %4 = fadd double %2, %3
  %5 = tail call double @llvm.fabs.f64(double %3)
  %6 = tail call double @llvm.fabs.f64(double %2)
  %7 = fcmp ole double %6, %5
  %8 = fsub double %2, %4
  %9 = fadd double %3, %8
  %10 = fsub double %3, %4
  %11 = fadd double %2, %10
  %12 = select i1 %7, double %11, double %9
  %13 = load double, ptr %1, align 8
  %14 = fadd double %13, %12
  store double %14, ptr %1, align 8
  store double %4, ptr %0, align 8
  ret void
}

; Function Attrs: mustprogress nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare double @llvm.fabs.f64(double) #1

attributes #0 = { mustprogress nofree norecurse nosync nounwind willreturn memory(argmem: readwrite) "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+altnzcv,+bti,+ccdp,+ccidx,+ccpp,+complxnum,+crc,+dit,+dotprod,+flagm,+fp-armv8,+fp16fml,+fptoint,+fullfp16,+jsconv,+lse,+neon,+pauth,+perfmon,+predres,+ras,+rcpc,+rdm,+sb,+sha2,+sha3,+specrestrict,+ssbs,+v8.1a,+v8.2a,+v8.3a,+v8.4a,+v8.5a,+v8a" }
attributes #1 = { mustprogress nocallback nofree nosync nounwind speculatable willreturn memory(none) }

!llvm.module.flags = !{!0, !1, !2, !3, !4, !5, !6, !7, !8, !9, !10, !11}
!swift.module.flags = !{!12}
!llvm.linker.options = !{!13, !14, !15, !16}

!0 = !{i32 2, !"SDK Version", [2 x i32] [i32 27, i32 0]}
!1 = !{i32 1, !"Objective-C Version", i32 2}
!2 = !{i32 1, !"Objective-C Image Info Version", i32 0}
!3 = !{i32 1, !"Objective-C Image Info Section", !"__DATA,__objc_imageinfo,regular,no_dead_strip"}
!4 = !{i32 4, !"Objective-C Garbage Collection", i32 100927232}
!5 = !{i32 1, !"Objective-C Class Properties", i32 64}
!6 = !{i32 1, !"Objective-C Enforce ClassRO Pointer Signing", i8 0}
!7 = !{i32 1, !"wchar_size", i32 4}
!8 = !{i32 8, !"PIC Level", i32 2}
!9 = !{i32 7, !"uwtable", i32 1}
!10 = !{i32 7, !"frame-pointer", i32 1}
!11 = !{i32 1, !"Swift Version", i32 7}
!12 = !{!"standard-library", i1 false}
!13 = !{!"-lswift_Concurrency"}
!14 = !{!"-lswiftCore"}
!15 = !{!"-lswift_StringProcessing"}
!16 = !{!"-lobjc"}
