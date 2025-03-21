.. _overview_section_tag:

Overview
========

NekROM is a POD-Galerkin reduced-order modeling library to enable model-order-reduction (MOR) of Nek5000 simulations. 

Capabilities of NekROM include:

* Support for reading in Nek5000 outputs as snapshot data
* Support for saving ROM outputs to Nek5000 output formats
* CP decomposition to reduce the cost of the rank three convection tensor
* Stabilization methods such as constrained ROM, time-relaxation, evolve-filter-relax, and Leray regularization.
