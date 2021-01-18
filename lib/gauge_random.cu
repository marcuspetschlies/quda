#include <quda_internal.h>
#include <gauge_field.h>
#include <instantiate.h>
#include <tunable_nd.h>
#include <kernels/gauge_random.cuh>

namespace quda {

  template <typename Float, int nColor, QudaReconstructType recon>
  class GaugeGauss : TunableKernel2D
  {
    GaugeField &U;
    RNG &rng;
    Float sigma;
    bool group;
    unsigned int minThreads() const { return U.VolumeCB(); }

  public:
    GaugeGauss(GaugeField &U, RNG &rng, double sigma) :
      TunableKernel2D(U, 2),
      U(U),
      rng(rng),
      sigma(static_cast<Float>(sigma)),
      group(U.LinkType() == QUDA_SUN_LINKS)
    {
      if (getVerbosity() >= QUDA_SUMMARIZE) {
        if (group) printfQuda("Creating Gaussian distrbuted Lie group field with sigma = %e\n", sigma);
        else printfQuda("Creating Gaussian distrbuted Lie algebra field\n");
      }
      strcat(aux, group ? ",lie_group" : "lie_algebra");
      apply(device::get_default_stream());
    }

    void apply(const qudaStream_t &stream)
    {
      TuneParam tp = tuneLaunch(*this, getTuning(), getVerbosity());
      if (group) {
        launch<GaussGauge>(tp, stream, GaugeGaussArg<Float, nColor, recon, true>(U, rng, sigma));
      } else {
        launch<GaussGauge>(tp, stream, GaugeGaussArg<Float, nColor, recon, false>(U, rng, sigma));
      }
    }

    long long flops() const { return 0; }
    long long bytes() const { return U.Bytes(); }

    void preTune() { rng.backup(); }
    void postTune() { rng.restore(); }
  };

  void gaugeGauss(GaugeField &U, RNG &rng, double sigma)
  {
    if (!U.isNative()) errorQuda("Order %d with %d reconstruct not supported", U.Order(), U.Reconstruct());
    if (U.LinkType() != QUDA_SUN_LINKS && U.LinkType() != QUDA_MOMENTUM_LINKS)
      errorQuda("Unexpected link type %d", U.LinkType());

    instantiate<GaugeGauss, ReconstructFull>(U, rng, sigma);

    // ensure multi-gpu consistency if required
    if (U.GhostExchange() == QUDA_GHOST_EXCHANGE_EXTENDED) {
      U.exchangeExtendedGhost(U.R());
    } else if (U.GhostExchange() == QUDA_GHOST_EXCHANGE_PAD) {
      U.exchangeGhost();
    }
  }

  void gaugeGauss(GaugeField &U, unsigned long long seed, double sigma)
  {
    RNG *randstates = new RNG(U, seed);
    randstates->Init();
    quda::gaugeGauss(U, *randstates, sigma);
    randstates->Release();
    delete randstates;
  }
}
