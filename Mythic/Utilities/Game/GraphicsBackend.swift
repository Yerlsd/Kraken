//
//  GraphicsBackend.swift
//  Kraken
//
// Copyright © 2026 Kraken contributors

import Foundation

/// Graphics backend for Wine 11 D3D translation.
///
/// Determines which translation layer Wine uses to render DirectX content:
/// - D3DMetal: Apple Game Porting Toolkit D3D→Metal translation
/// - DXMT: Open-source D3D10/D3D11→Metal translation
/// - DXVK: D3D9/D3D10/D3D11→Vulkan→MoltenVK→Metal
/// - WineD3D: Wine's built-in OpenGL-based D3D implementation
/// - Automatic: Kraken selects based on game requirements and available backends
enum GraphicsBackend: String, Codable, CaseIterable, Sendable {
    case automatic
    case d3dmetal
    case dxmt
    case dxvk
    case wined3d

    var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .d3dmetal: return "D3DMetal"
        case .dxmt: return "DXMT"
        case .dxvk: return "DXVK"
        case .wined3d: return "WineD3D"
        }
    }

    /// DirectX API support for this backend.
    var capabilities: GraphicsBackendCapabilities {
        switch self {
        case .automatic:
            return GraphicsBackendCapabilities(
                supportsD3D9: true,
                supportsD3D10: true,
                supportsD3D11: true,
                supportsD3D12: true
            )
        case .d3dmetal:
            return GraphicsBackendCapabilities(
                supportsD3D9: false,
                supportsD3D10: true,
                supportsD3D11: true,
                supportsD3D12: true
            )
        case .dxmt:
            return GraphicsBackendCapabilities(
                supportsD3D9: false,
                supportsD3D10: true,
                supportsD3D11: true,
                supportsD3D12: false
            )
        case .dxvk:
            return GraphicsBackendCapabilities(
                supportsD3D9: true,
                supportsD3D10: true,
                supportsD3D11: true,
                supportsD3D12: false
            )
        case .wined3d:
            return GraphicsBackendCapabilities(
                supportsD3D9: true,
                supportsD3D10: true,
                supportsD3D11: true,
                supportsD3D12: true
            )
        }
    }
}

/// DirectX API version support for a graphics backend.
struct GraphicsBackendCapabilities: Sendable {
    let supportsD3D9: Bool
    let supportsD3D10: Bool
    let supportsD3D11: Bool
    let supportsD3D12: Bool
}
