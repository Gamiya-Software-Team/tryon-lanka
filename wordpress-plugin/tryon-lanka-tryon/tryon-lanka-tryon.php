<?php
/**
 * Plugin Name: TRYON LANKA Try-On Settings
 * Description: Adds live virtual try-on settings (garment cutout + calibration) to WooCommerce products and exposes them to the TRYON LANKA mobile app through the standard WooCommerce product meta_data.
 * Version: 1.0.0
 * Author: Gamiya Software Team
 * Requires Plugins: woocommerce
 * License: GPL-2.0-or-later
 */

if (!defined('ABSPATH')) {
    exit;
}

final class TryOn_Lanka_Settings
{
    /** Meta keys must NOT start with "_" so WooCommerce REST returns them. */
    const FIELDS = [
        'tryon_enabled'             => ['label' => 'Enable live try-on', 'type' => 'checkbox'],
        'tryon_garment_url'         => ['label' => 'Transparent garment image URL (PNG/WebP, front-facing cutout, https)', 'type' => 'url'],
        'tryon_garment_type'        => ['label' => 'Garment type', 'type' => 'select', 'options' => ['tshirt' => 'T-shirt', 'shirt' => 'Shirt', 'hoodie' => 'Hoodie (future)', 'dress' => 'Dress (future)']],
        'tryon_width_ratio'         => ['label' => 'Width ratio (x shoulder width)', 'type' => 'number', 'default' => '1.9', 'min' => '0.5', 'max' => '4'],
        'tryon_height_ratio'        => ['label' => 'Height ratio (x torso length, used without image)', 'type' => 'number', 'default' => '1.45', 'min' => '0.5', 'max' => '4'],
        'tryon_offset_x'            => ['label' => 'Horizontal offset (fraction of width)', 'type' => 'number', 'default' => '0', 'min' => '-1', 'max' => '1'],
        'tryon_offset_y'            => ['label' => 'Vertical offset (fraction of height, negative = up)', 'type' => 'number', 'default' => '-0.10', 'min' => '-1', 'max' => '1'],
        'tryon_rotation'            => ['label' => 'Extra rotation (degrees)', 'type' => 'number', 'default' => '0', 'min' => '-45', 'max' => '45'],
        'tryon_scale'               => ['label' => 'Scale', 'type' => 'number', 'default' => '1', 'min' => '0.3', 'max' => '3'],
        'tryon_calibration_version' => ['label' => 'Calibration version', 'type' => 'number', 'default' => '1', 'min' => '1', 'max' => '999'],
    ];

    public static function init()
    {
        add_filter('woocommerce_product_data_tabs', [__CLASS__, 'tab']);
        add_action('woocommerce_product_data_panels', [__CLASS__, 'panel']);
        add_action('woocommerce_admin_process_product_object', [__CLASS__, 'save']);
        add_action('init', [__CLASS__, 'register_meta']);
        add_action('rest_api_init', [__CLASS__, 'routes']);
    }

    public static function tab($tabs)
    {
        $tabs['tryon_lanka'] = [
            'label'    => __('Live Try-On', 'tryon-lanka'),
            'target'   => 'tryon_lanka_panel',
            'priority' => 80,
        ];
        return $tabs;
    }

    public static function panel()
    {
        global $post;
        echo '<div id="tryon_lanka_panel" class="panel woocommerce_options_panel"><div class="options_group">';
        wp_nonce_field('tryon_lanka_save', 'tryon_lanka_nonce');
        foreach (self::FIELDS as $key => $f) {
            $value = get_post_meta($post->ID, $key, true);
            if ($value === '' && isset($f['default'])) {
                $value = $f['default'];
            }
            switch ($f['type']) {
                case 'checkbox':
                    woocommerce_wp_checkbox(['id' => $key, 'label' => $f['label'], 'value' => $value === 'yes' ? 'yes' : 'no']);
                    break;
                case 'select':
                    woocommerce_wp_select(['id' => $key, 'label' => $f['label'], 'options' => $f['options'], 'value' => $value ?: 'tshirt']);
                    break;
                case 'url':
                    woocommerce_wp_text_input(['id' => $key, 'label' => $f['label'], 'type' => 'url', 'value' => $value, 'placeholder' => 'https://']);
                    break;
                default:
                    woocommerce_wp_text_input([
                        'id' => $key, 'label' => $f['label'], 'type' => 'number', 'value' => $value,
                        'custom_attributes' => ['step' => '0.01', 'min' => $f['min'], 'max' => $f['max']],
                    ]);
            }
        }
        echo '<p class="form-field"><em>Use a transparent, front-facing garment cutout. Do not use model photographs. The app falls back to a demo silhouette if the image is missing.</em></p>';
        echo '</div></div>';
    }

    /** @param WC_Product $product */
    public static function save($product)
    {
        if (!isset($_POST['tryon_lanka_nonce']) || !wp_verify_nonce(sanitize_text_field(wp_unslash($_POST['tryon_lanka_nonce'])), 'tryon_lanka_save')) {
            return;
        }
        if (!current_user_can('edit_product', $product->get_id())) {
            return;
        }
        foreach (self::FIELDS as $key => $f) {
            $raw = isset($_POST[$key]) ? wp_unslash($_POST[$key]) : '';
            switch ($f['type']) {
                case 'checkbox':
                    $product->update_meta_data($key, $raw === 'yes' ? 'yes' : 'no');
                    break;
                case 'url':
                    $url = esc_url_raw(trim($raw), ['https']);
                    $product->update_meta_data($key, $url);
                    break;
                case 'select':
                    $product->update_meta_data($key, array_key_exists($raw, $f['options']) ? $raw : 'tshirt');
                    break;
                default:
                    $num = is_numeric($raw) ? (float) $raw : (float) $f['default'];
                    $num = max((float) $f['min'], min((float) $f['max'], $num));
                    $product->update_meta_data($key, (string) $num);
            }
        }
    }

    public static function register_meta()
    {
        foreach (array_keys(self::FIELDS) as $key) {
            register_post_meta('product', $key, [
                'type'          => 'string',
                'single'        => true,
                'show_in_rest'  => true,
                'auth_callback' => function () {
                    return current_user_can('edit_products');
                },
            ]);
        }
    }

    /**
     * Public read-only endpoint: GET /wp-json/tryon-lanka/v1/product/{id}
     * Variations inherit the parent's try-on settings unless they set their own.
     */
    public static function routes()
    {
        register_rest_route('tryon-lanka/v1', '/product/(?P<id>\d+)', [
            'methods'             => 'GET',
            'permission_callback' => '__return_true',
            'args'                => ['id' => ['validate_callback' => 'is_numeric']],
            'callback'            => function (WP_REST_Request $req) {
                $product = wc_get_product((int) $req['id']);
                if (!$product || $product->get_status() !== 'publish') {
                    return new WP_Error('not_found', 'Product not found', ['status' => 404]);
                }
                $source = $product;
                if ($product->is_type('variation') && $product->get_meta('tryon_enabled') === '') {
                    $source = wc_get_product($product->get_parent_id());
                }
                $out = ['product_id' => $product->get_id()];
                foreach (array_keys(self::FIELDS) as $key) {
                    $out[$key] = $source ? $source->get_meta($key) : '';
                }
                return rest_ensure_response($out);
            },
        ]);
    }
}

TryOn_Lanka_Settings::init();
